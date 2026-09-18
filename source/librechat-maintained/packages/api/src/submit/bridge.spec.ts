import { once } from 'node:events';
import { Readable } from 'node:stream';
import { createServer } from 'node:http';
import { createHash } from 'node:crypto';
import type { Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import type { SubmitBridgeConfig, SubmitUpload } from './bridge';
import { stageSubmitFile, submitHeaders, SUBMIT_MAX_BYTES } from './bridge';

const pdf = Buffer.from('%PDF-1.7\ncontrolled-upload-test');
const attachmentId = 'att_abcdefghijklmnopqrstuvwx';
const digest = createHash('sha256').update(pdf).digest('hex');
const upload: SubmitUpload = {
  fileId: 'file-1',
  filename: 'source.pdf',
  contentType: 'application/pdf',
  contentLength: pdf.length,
  open: async () => Readable.from([pdf]),
};

describe('Submit HTTP attachment bridge', () => {
  let server: Server;
  let config: SubmitBridgeConfig;
  let requests: Array<{
    headers: Record<string, string | string[] | undefined>;
    body: Buffer;
    url?: string;
  }>;
  let status: number;
  let hash: string;
  let redirect: boolean;

  beforeAll(async () => {
    server = createServer(async (req, res) => {
      const chunks: Buffer[] = [];
      for await (const chunk of req) chunks.push(Buffer.from(chunk));
      requests.push({ headers: req.headers, body: Buffer.concat(chunks), url: req.url });
      res.writeHead(redirect ? 302 : status, {
        'Content-Type': 'application/json',
        ...(redirect ? { Location: '/redirect-target' } : {}),
      });
      res.end(
        JSON.stringify({
          attachment_id: attachmentId,
          status: 'uploaded',
          file_name: upload.filename,
          size: pdf.length,
          sha256: hash,
        }),
      );
    }).listen(0, '127.0.0.1');
    await once(server, 'listening');
    config = {
      endpoint: `http://127.0.0.1:${(server.address() as AddressInfo).port}/mcp`,
      authorization: 'Bearer isolated-test-token',
      tenantId: 'test-tenant',
      userId: 'user-1',
      userRole: 'USER',
      conversationId: 'conversation-1',
      agentId: 'smart-submit-v1',
      agentVersion: '1.0.0',
    };
  });
  beforeEach(() => {
    requests = [];
    status = 201;
    hash = digest;
    redirect = false;
  });
  afterAll(async () => {
    server.closeAllConnections();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  });

  test('sends intact PDF and complete identity, without pretending to bind a task', async () => {
    const result = await stageSubmitFile(config, upload);
    expect(result.attachment_id).toBe(attachmentId);
    expect(requests).toHaveLength(1);
    expect(requests[0].url).toBe('/v1/attachments');
    expect(requests[0].headers['x-librechat-user-role']).toBe('USER');
    expect(requests[0].headers['x-agentos-conversation-id']).toBe('conversation-1');
    expect(requests[0].headers.authorization).toBe(config.authorization);
    expect(requests[0].body.includes(pdf)).toBe(true);
    expect(requests[0].body.toString()).not.toContain('name="task_id"');
  });
  test('retry key is stable, but changes with conversation and content', async () => {
    await stageSubmitFile(config, upload);
    await stageSubmitFile(config, upload);
    await stageSubmitFile({ ...config, conversationId: 'conversation-2' }, upload);
    const keys = requests.map((request) => request.headers['idempotency-key']);
    expect(keys[0]).toBe(keys[1]);
    expect(keys[0]).not.toBe(keys[2]);
  });
  test.each([
    { contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' },
    { filename: '../source.pdf' },
    { filename: 'source.xlsx' },
    { contentLength: SUBMIT_MAX_BYTES + 1 },
    { contentLength: 0 },
  ])('rejects invalid metadata before reading/uploading: %j', async (change) => {
    await expect(stageSubmitFile(config, { ...upload, ...change })).rejects.toThrow();
    expect(requests).toHaveLength(0);
  });
  test('rejects forged PDF, oversized stream and truncated stream', async () => {
    for (const bytes of [Buffer.from('wrong'), Buffer.concat([pdf, pdf]), pdf.subarray(0, 8)]) {
      await expect(
        stageSubmitFile(config, { ...upload, open: async () => Readable.from([bytes]) }),
      ).rejects.toThrow();
    }
    expect(requests).toHaveLength(0);
  });
  test('requires all identity fields and resolved credentials', () => {
    expect(() => submitHeaders({ ...config, userRole: '' })).toThrow();
    expect(() =>
      submitHeaders({ ...config, authorization: 'Bearer ${SUBMIT_MCP_TOKEN}' }),
    ).toThrow();
  });
  test('does not follow a redirect carrying the service credential', async () => {
    redirect = true;
    await expect(stageSubmitFile(config, upload)).rejects.toThrow();
    expect(requests).toHaveLength(1);
  });
  test('surfaces failure instead of returning a fabricated attachment', async () => {
    status = 403;
    await expect(stageSubmitFile(config, upload)).rejects.toThrow('(403)');
  });
  test('verifies returned integrity evidence', async () => {
    hash = '0'.repeat(64);
    await expect(stageSubmitFile(config, upload)).rejects.toThrow('integrity');
  });
  test.each([
    'file:///tmp/mcp',
    'http://localhost:8121/elsewhere',
    'http://user:pass@localhost/mcp',
  ])('rejects unsafe configured endpoint %s', async (endpoint) => {
    await expect(stageSubmitFile({ ...config, endpoint }, upload)).rejects.toThrow();
    expect(requests).toHaveLength(0);
  });
});
