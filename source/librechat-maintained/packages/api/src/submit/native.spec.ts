import type { MCPOptions } from 'librechat-data-provider';
import type { ServerRequest } from '~/types';
import { primeNativeSubmit } from './native';

const req = {
  user: { id: 'user-a', role: 'USER' },
  body: { conversationId: 'conversation-a', parentMessageId: 'parent-a' },
} as ServerRequest;
const options: MCPOptions = {
  type: 'streamable-http',
  url: 'http://127.0.0.1:1/mcp',
  headers: {
    Authorization: 'Bearer test-token',
    'X-AgentOS-Tenant-Id': 'test-tenant',
    'X-AgentOS-Agent-Id': 'smart-submit-v1',
    'X-AgentOS-Agent-Version': '1.0.0',
  },
};

describe('native Submit run context', () => {
  const deps = {
    getMessages: async () => [],
    getFiles: async () => [],
    getStrategyFunctions: () => {
      throw new Error('Storage must not be read');
    },
  };
  const input = () => ({
    req,
    options,
    agentId: 'agent_smart_submit_v1',
    canUseMCP: true,
    fileIds: [],
    deps,
  });
  test('does not upload for a conversation with no attachments', async () => {
    await expect(primeNativeSubmit(input())).resolves.toBe('');
  });
  test('requires MCP permission even for an accessible Agent', async () => {
    await expect(primeNativeSubmit({ ...input(), canUseMCP: false })).rejects.toThrow('MCP access');
  });
  test('rejects user-sourced servers and a different Agent binding', async () => {
    await expect(
      primeNativeSubmit({ ...input(), options: { ...options, dbId: 'user-server' } }),
    ).rejects.toThrow('operator-managed');
    await expect(primeNativeSubmit({ ...input(), agentId: 'other-agent' })).rejects.toThrow(
      'binding',
    );
  });
  test('rehydrates only the current parent branch and merges current file IDs', async () => {
    let selected: string[] = [];
    await expect(
      primeNativeSubmit({
        ...input(),
        fileIds: ['current-file'],
        deps: {
          ...deps,
          getMessages: async (filter, fields) => {
            expect(filter).toEqual({ conversationId: 'conversation-a', user: 'user-a' });
            expect(fields).toBe('messageId parentMessageId files');
            return [
              { messageId: 'parent-a', parentMessageId: null, files: [{ file_id: 'prior-file' }] },
              {
                messageId: 'other-branch',
                parentMessageId: null,
                files: [{ file_id: 'unrelated-file' }],
              },
            ];
          },
          getFiles: async (filter) => {
            selected = filter.file_id.$in;
            return [];
          },
        },
      }),
    ).rejects.toThrow('unavailable');
    expect(selected).toEqual(['prior-file', 'current-file']);
  });
});
