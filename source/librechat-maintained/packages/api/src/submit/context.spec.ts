import { Types } from 'mongoose';
import type { ServerRequest } from '~/types';
import type { SubmitBridgeConfig } from './bridge';
import type { SubmitStoredFile } from './context';
import { primeSubmitAttachments } from './context';

const owner = new Types.ObjectId();
const config: SubmitBridgeConfig = {
  endpoint: 'http://127.0.0.1:1/mcp',
  authorization: 'Bearer unit-test-token',
  tenantId: 'tenant-1',
  userId: owner.toString(),
  userRole: 'USER',
  conversationId: 'conversation-1',
  agentId: 'smart-submit-v1',
  agentVersion: '1.0.0',
};
const req = {
  user: { id: config.userId, role: 'USER', tenantId: 'tenant-1' },
  body: { conversationId: config.conversationId },
} as ServerRequest;
const file: SubmitStoredFile = {
  file_id: 'file-1',
  user: owner,
  tenantId: 'tenant-1',
  source: 'local',
  filename: 'source.pdf',
  filepath: `/uploads/${owner}/source.pdf`,
  type: 'application/pdf',
  bytes: 20,
};

describe('Submit native attachment access boundary', () => {
  const invoke = (records: SubmitStoredFile[], fileIds = ['file-1'], request = req) =>
    primeSubmitAttachments({
      req: request,
      config,
      fileIds,
      deps: {
        getFiles: async (filter) => {
          expect(filter.user).toBe(config.userId);
          expect(filter.tenantId).toBe('tenant-1');
          return records;
        },
        getStrategyFunctions: () => {
          throw new Error('MUST NOT OPEN STORAGE');
        },
      },
    });
  test('empty input has no broker work', async () => {
    await expect(invoke([], [])).resolves.toBe('');
  });
  test.each([
    { records: [] },
    { records: [{ ...file, user: new Types.ObjectId() }] },
    { records: [{ ...file, tenantId: 'other-tenant' }] },
  ])('rejects missing or non-owned records', async ({ records }) => {
    await expect(invoke(records)).rejects.toThrow('unavailable or belongs');
  });
  test.each([
    'C:\\private\\source.pdf',
    'http://localhost/private',
    `/uploads/${owner}/../private.pdf`,
    `/uploads/other/source.pdf`,
  ])('rejects unsafe stored location %s', async (filepath) => {
    await expect(invoke([{ ...file, filepath }])).rejects.toThrow('locally stored');
  });
  test('validates entire batch before staging any file', async () => {
    await expect(
      invoke([file, { ...file, file_id: 'file-2', type: 'text/plain' }], ['file-1', 'file-2']),
    ).rejects.toThrow('source PDFs only');
  });
  test('rejects identity and conversation substitution', async () => {
    await expect(
      invoke([file], ['file-1'], {
        ...req,
        body: { conversationId: 'other-conversation' },
      } as ServerRequest),
    ).rejects.toThrow('identity');
  });
  test('bounds total files and disallows path-like IDs', async () => {
    await expect(invoke([file], Array(11).fill('file-1'))).rejects.toThrow('at most 10');
    await expect(invoke([file], ['../../file'])).rejects.toThrow('identifiers');
  });
  test.each([{ expiredAt: new Date() }, { expiresAt: new Date(0) }])(
    'does not bypass file retention: %j',
    async (expiry) => {
      await expect(invoke([{ ...file, ...expiry }])).rejects.toThrow('expired');
    },
  );
});
