import { z } from 'zod';
import { once } from 'node:events';
import { Readable } from 'node:stream';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import type { ChildProcessWithoutNullStreams } from 'node:child_process';
import type { SubmitBridgeConfig } from './bridge';
import { stageSubmitFile, submitHeaders } from './bridge';
import { getSubmitSnapshot, downloadSubmitArtifact } from './proxy';

// This fixture imports the actual Submit adapter but confines all writes to a temporary runtime.
const bootstrap = `
import sys, tempfile, threading, json
from pathlib import Path
root = Path(sys.argv[1]).resolve()
sys.path[:0] = [str(root / 'src'), str(root)]
from submit_flow_agent.http_service import ServiceConfig, build_server
from tests.pricing_helpers import create_task_with_pricing
from submit_flow_agent.task_store import load_task, write_task
with tempfile.TemporaryDirectory(prefix='agentos-submit-contract-') as temporary:
    runtime = Path(temporary) / 'runtime'
    config_path = root / 'config' / 'sites.json'
    create_task_with_pricing(runtime, task_id='pricing-seed', month='2026-05', config_path=config_path)
    config = ServiceConfig(runtime_root=runtime, config_path=config_path,
        token='isolated-integration-token', tenant_id='test-tenant',
        agent_id='smart-submit-v1', agent_version='1.0.0')
    server = build_server(config, host='127.0.0.1', port=0)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    print(server.server_address[1], flush=True)
    for line in sys.stdin:
        if line.strip() == 'quit': break
        task_id = json.loads(line)['complete']
        task_root = runtime / 'tasks' / task_id
        task = load_task(task_root)
        artifact = task_root / 'outputs' / 'report.xlsx'
        artifact.parent.mkdir(parents=True, exist_ok=True)
        artifact.write_bytes(b'PK-test-artifact-transport-only')
        task['outputs'] = [str(artifact)]
        task['status'] = 'completed'
        write_task(task_root, task)
        print('completed', flush=True)
    server.shutdown()
    thread.join()
    server.server_close()
`;

const projectRoot = process.env.SUBMIT_TEST_PROJECT_ROOT;
const suite = projectRoot ? describe : describe.skip;

suite('real Submit adapter and MCP SDK contract (isolated runtime)', () => {
  let child: ChildProcessWithoutNullStreams;
  let client: Client;
  let config: SubmitBridgeConfig;

  beforeAll(async () => {
    child = spawn(
      process.env.SUBMIT_TEST_PYTHON || 'python',
      ['-u', '-c', bootstrap, projectRoot!],
      {
        windowsHide: true,
      },
    );
    const lines = createInterface({ input: child.stdout });
    const port = await new Promise<string>((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error('Isolated Submit adapter startup timed out')),
        20_000,
      );
      child.once('error', (error) => {
        clearTimeout(timer);
        reject(error);
      });
      child.once('exit', (code) => {
        clearTimeout(timer);
        reject(new Error(`Submit fixture exited: ${code}`));
      });
      lines.once('line', (line) => {
        clearTimeout(timer);
        resolve(line);
      });
    });
    lines.close();
    if (!/^\d+$/.test(port)) throw new Error('Submit fixture did not provide a local port');
    config = {
      endpoint: `http://127.0.0.1:${port}/mcp`,
      authorization: 'Bearer isolated-integration-token',
      tenantId: 'test-tenant',
      userId: 'user-a',
      userRole: 'USER',
      conversationId: 'conversation-a',
      agentId: 'smart-submit-v1',
      agentVersion: '1.0.0',
    };
    client = new Client({ name: 'agentos-contract-test', version: '1.0.0' });
    await client.connect(
      new StreamableHTTPClientTransport(new URL(config.endpoint), {
        requestInit: { headers: submitHeaders(config) },
      }),
    );
  }, 30_000);

  afterAll(async () => {
    await client?.close();
    if (!child || child.exitCode !== null) return;
    const closed = once(child, 'exit');
    child.stdin.end('quit\n');
    const timer = setTimeout(() => child.kill(), 5_000);
    try {
      await closed;
    } finally {
      clearTimeout(timer);
    }
  });

  test('uploads idempotently, binds through real MCP, and rejects another owner', async () => {
    const tools = await client.listTools();
    expect(tools.tools.map((tool) => tool.name)).toContain('submit_flow.attach_file');
    const created = await client.callTool({
      name: 'submit_flow.create_task',
      arguments: {
        site_key: 'xinan_high_school',
        month: '2026-05',
      },
    });
    expect(created.isError).not.toBe(true);
    const { task_id } = z.object({ task_id: z.string() }).parse(created.structuredContent);
    const bytes = Buffer.from('%PDF-1.7\ncontrolled-test-pdf');
    const upload = {
      fileId: 'native-file-1',
      filename: 'source.pdf',
      contentType: 'application/pdf',
      contentLength: bytes.length,
      open: async () => Readable.from([bytes]),
    };
    const staged = await stageSubmitFile(config, upload);
    expect((await stageSubmitFile(config, upload)).attachment_id).toBe(staged.attachment_id);
    const attached = await client.callTool({
      name: 'submit_flow.attach_file',
      arguments: {
        task_id,
        attachment_id: staged.attachment_id,
      },
    });
    expect(attached.isError).not.toBe(true);
    const task = await client.callTool({ name: 'submit_flow.get_task', arguments: { task_id } });
    expect(task.isError).not.toBe(true);
    expect(task.structuredContent).toEqual(
      expect.objectContaining({ task_id, status: 'collecting_files' }),
    );
    const pending = await getSubmitSnapshot(config, task_id);
    expect(pending.artifacts).toHaveLength(0);

    const lines = createInterface({ input: child.stdout });
    const fixtureReady = once(lines, 'line');
    child.stdin.write(JSON.stringify({ complete: task_id }) + '\n');
    expect((await fixtureReady)[0]).toBe('completed');
    lines.close();
    const completed = await getSubmitSnapshot(config, task_id);
    expect(completed.artifacts).toHaveLength(1);
    expect(JSON.stringify(completed)).not.toContain('download_url');
    expect(JSON.stringify(completed)).not.toContain('runtime');
    const downloaded = await downloadSubmitArtifact(
      config,
      task_id,
      completed.artifacts[0].artifact_id,
    );
    expect(downloaded.bytes.toString()).toBe('PK-test-artifact-transport-only');
    await expect(
      getSubmitSnapshot({ ...config, conversationId: 'different-conversation' }, task_id),
    ).rejects.toThrow('unavailable');

    const other = new Client({ name: 'other-user', version: '1.0.0' });
    try {
      await other.connect(
        new StreamableHTTPClientTransport(new URL(config.endpoint), {
          requestInit: { headers: submitHeaders({ ...config, userId: 'user-b' }) },
        }),
      );
      const denied = await other.callTool({ name: 'submit_flow.get_task', arguments: { task_id } });
      expect(denied.isError).toBe(true);
      const deniedAttachment = await other.callTool({
        name: 'submit_flow.attach_file',
        arguments: {
          task_id,
          attachment_id: staged.attachment_id,
        },
      });
      expect(deniedAttachment.isError).toBe(true);
    } finally {
      await other.close();
    }
  });
});
