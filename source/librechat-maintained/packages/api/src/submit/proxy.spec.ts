import express from 'express';
import { once } from 'node:events';
import { createServer } from 'node:http';
import type { AddressInfo } from 'node:net';
import type { SubmitArtifact } from 'librechat-data-provider';
import type { ServerRequest } from '~/types';
import { downloadableSubmitArtifact, handleSubmitProxy } from './proxy';

describe('Submit report proxy authorization', () => {
  const artifact: SubmitArtifact = {
    artifact_id: 'art_abcdefghijklmnopqr',
    file_name: 'report.xlsx',
    size: 10,
    sha256: '0'.repeat(64),
    status: 'available',
    kind: 'output',
    role: 'output',
  };
  test.each([
    { kind: 'source_pdf' },
    { status: 'missing' },
    { file_name: '../report.xlsx' },
    { file_name: 'source.pdf' },
    { file_name: 'report.xlsx\r\nInjected' },
  ])('does not expose non-report or unsafe artifact %j', (change) => {
    expect(downloadableSubmitArtifact({ ...artifact, ...change })).toBe(false);
  });
  test('accepts an available Excel report', () => {
    expect(downloadableSubmitArtifact(artifact)).toBe(true);
  });
  test('rejects absent identity, wrong Agent and unowned conversations before accessing Submit', async () => {
    const app = express();
    let requestsToSubmit = 0;
    app.get('/:id/submit/:conversationId/:taskId', async (req, res) => {
      const request = req as Parameters<typeof handleSubmitProxy>[0];
      if (req.headers['x-test-user'])
        request.user = { id: 'user-a', role: 'USER' } as ServerRequest['user'];
      await handleSubmitProxy(request, res, {
        getConvo: async () => null,
        canUseMCP: async () => true,
        resolveConfigServers: async () => {
          requestsToSubmit += 1;
          return {};
        },
      });
    });
    const server = createServer(app).listen(0, '127.0.0.1');
    await once(server, 'listening');
    const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
    const path = '/smart-submit-v1/submit/123e4567-e89b-42d3-a456-426614174000/task-a';
    try {
      expect((await fetch(base + path)).status).toBe(403);
      expect((await fetch(base + path, { headers: { 'X-Test-User': 'yes' } })).status).toBe(403);
      expect(
        (
          await fetch(base + path.replace('smart-submit-v1', 'other-agent'), {
            headers: { 'X-Test-User': 'yes' },
          })
        ).status,
      ).toBe(403);
      expect(requestsToSubmit).toBe(0);
    } finally {
      server.closeAllConnections();
      await new Promise<void>((resolve) => server.close(() => resolve()));
    }
  });
});
