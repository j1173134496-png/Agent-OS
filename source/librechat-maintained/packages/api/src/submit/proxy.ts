import { z } from 'zod';
import { createHash } from 'node:crypto';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { submitTaskSchema, submitOutputsSchema } from 'librechat-data-provider';
import type { MCPOptions, SubmitSnapshot, SubmitArtifact } from 'librechat-data-provider';
import type { Request, Response } from 'express';
import type { ServerRequest } from '~/types';
import type { SubmitBridgeConfig } from './bridge';
import { resolveSubmitConfig } from './config';
import { submitHeaders, validateSubmitEndpoint } from './bridge';

export class SubmitProxyError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

export function downloadableSubmitArtifact(artifact: SubmitArtifact): boolean {
  return (
    artifact.kind !== 'source_pdf' &&
    artifact.status === 'available' &&
    /\.xlsx$/i.test(artifact.file_name) &&
    !/[\\/]/.test(artifact.file_name) &&
    ![...artifact.file_name].some((character) => character.charCodeAt(0) < 32)
  );
}

async function readTool(client: Client, name: string, taskId: string) {
  const result = await client.callTool({ name, arguments: { task_id: taskId } });
  if (result.isError)
    throw new SubmitProxyError(403, 'Submit task is unavailable for this conversation');
  return result.structuredContent;
}

export async function getSubmitSnapshot(
  config: SubmitBridgeConfig,
  taskId: string,
): Promise<SubmitSnapshot> {
  if (!/^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$/.test(taskId))
    throw new SubmitProxyError(400, 'Invalid task identifier');
  const client = new Client({ name: 'agentos-submit-view', version: '1.0.0' });
  try {
    await client.connect(
      new StreamableHTTPClientTransport(new URL(config.endpoint), {
        requestInit: {
          headers: submitHeaders(config),
          redirect: 'error',
          signal: AbortSignal.timeout(15_000),
        },
      }),
    );
    const task = submitTaskSchema.parse(await readTool(client, 'submit_flow.get_task', taskId));
    if (task.task_id !== taskId || task.site_key !== 'xinan_high_school') {
      throw new SubmitProxyError(403, 'This release supports the configured single site only');
    }
    if (task.status !== 'completed') return { task, artifacts: [] };
    const outputs = submitOutputsSchema.parse(
      await readTool(client, 'submit_flow.list_outputs', taskId),
    );
    if (outputs.task_id !== taskId)
      throw new SubmitProxyError(502, 'Submit output binding is invalid');
    return { task, artifacts: outputs.artifacts.filter(downloadableSubmitArtifact) };
  } finally {
    await client.close();
  }
}

export async function downloadSubmitArtifact(
  config: SubmitBridgeConfig,
  taskId: string,
  artifactId: string,
): Promise<{ artifact: SubmitArtifact; bytes: Buffer }> {
  if (!/^art_[A-Za-z0-9_-]{16,96}$/.test(artifactId))
    throw new SubmitProxyError(400, 'Invalid artifact identifier');
  const snapshot = await getSubmitSnapshot(config, taskId);
  const artifact = snapshot.artifacts.find((item) => item.artifact_id === artifactId);
  if (!artifact) throw new SubmitProxyError(404, 'Report is not available');
  const endpoint = new URL(config.endpoint);
  validateSubmitEndpoint(config.endpoint);
  endpoint.pathname = `/v1/tasks/${encodeURIComponent(taskId)}/artifacts/${encodeURIComponent(artifactId)}`;
  const response = await fetch(endpoint, {
    headers: submitHeaders(config),
    redirect: 'error',
    signal: AbortSignal.timeout(60_000),
  });
  if (!response.ok || !response.body) {
    await response.body?.cancel();
    throw new SubmitProxyError(response.status === 403 ? 403 : 502, 'Report download failed');
  }
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      size += chunk.value.length;
      if (size > artifact.size || size > 50 * 1024 * 1024) {
        throw new SubmitProxyError(502, 'Report exceeds its declared size');
      }
      chunks.push(chunk.value);
    }
  } finally {
    await reader.cancel();
  }
  const bytes = Buffer.concat(chunks);
  if (
    size !== artifact.size ||
    createHash('sha256').update(bytes).digest('hex') !== artifact.sha256
  ) {
    throw new SubmitProxyError(502, 'Report integrity verification failed');
  }
  return { artifact, bytes };
}

type ProxyRequest = ServerRequest &
  Request<{
    id: string;
    conversationId: string;
    taskId: string;
    artifactId?: string;
  }>;
type ProxyDeps = {
  getConvo: (
    userId: string,
    conversationId: string,
  ) => Promise<{
    agent_id?: string | null;
    tenantId?: string | null;
  } | null>;
  resolveConfigServers: (
    req: ServerRequest,
  ) => Promise<Record<string, MCPOptions & { dbId?: string }>>;
  canUseMCP: (req: ServerRequest) => Promise<boolean>;
};

export async function handleSubmitProxy(
  req: ProxyRequest,
  res: Response,
  deps: ProxyDeps,
): Promise<void> {
  try {
    const { id, conversationId, taskId, artifactId } = req.params;
    if (
      !req.user?.id ||
      id !== (process.env.SUBMIT_PLATFORM_AGENT_ID || 'agent_smart_submit_v1') ||
      !z.string().uuid().safeParse(conversationId).success ||
      !(await deps.canUseMCP(req))
    ) {
      throw new SubmitProxyError(403, 'Submit access denied');
    }
    const conversation = await deps.getConvo(req.user.id, conversationId);
    if (
      !conversation ||
      conversation.agent_id !== id ||
      (conversation.tenantId ?? null) !== (req.user.tenantId ?? null)
    ) {
      throw new SubmitProxyError(403, 'Conversation access denied');
    }
    const servers = await deps.resolveConfigServers(req);
    const config = resolveSubmitConfig({
      user: req.user,
      conversationId,
      agentId: id,
      options: servers['submit-flow'],
    });
    res.setHeader('Cache-Control', 'private, no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    if (!artifactId) {
      res.json(await getSubmitSnapshot(config, taskId));
      return;
    }
    const { artifact, bytes } = await downloadSubmitArtifact(config, taskId, artifactId);
    res.setHeader(
      'Content-Type',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    res.setHeader(
      'Content-Disposition',
      `attachment; filename=report.xlsx; filename*=UTF-8''${encodeURIComponent(artifact.file_name)}`,
    );
    res.send(bytes);
  } catch (error) {
    const status = error instanceof SubmitProxyError ? error.status : 502;
    res.status(status).json({
      error:
        status === 502 ? 'Submit service is unavailable' : 'Submit access or report is unavailable',
    });
  }
}
