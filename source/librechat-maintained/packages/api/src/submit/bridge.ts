import { z } from 'zod';
import { createHash } from 'node:crypto';
import type { Readable } from 'node:stream';

export type SubmitBridgeConfig = {
  endpoint: string;
  authorization: string;
  tenantId: string;
  userId: string;
  userRole: string;
  conversationId: string;
  agentId: string;
  agentVersion: string;
};

export type SubmitUpload = {
  fileId: string;
  filename: string;
  contentType: string;
  contentLength: number;
  open: () => Promise<Readable>;
};

export type SubmitAttachment = {
  attachment_id: string;
  status: 'uploaded';
  file_name: string;
  size: number;
  sha256: string;
};

const attachmentSchema: z.ZodType<SubmitAttachment> = z.object({
  attachment_id: z.string().regex(/^att_[A-Za-z0-9_-]{16,128}$/),
  status: z.literal('uploaded'),
  file_name: z.string(),
  size: z.number().int().positive(),
  sha256: z.string().regex(/^[a-f0-9]{64}$/),
});

export const SUBMIT_MAX_BYTES: number = 20 * 1024 * 1024;

export function submitHeaders(config: SubmitBridgeConfig): Record<string, string> {
  if (Object.values(config).some((value) => !value || /[\r\n]/.test(value))) {
    throw new Error('Submit identity or service configuration is missing');
  }
  if (!config.authorization.startsWith('Bearer ') || config.authorization.includes('${')) {
    throw new Error('Submit service authentication is not configured');
  }
  return {
    Authorization: config.authorization,
    'X-AgentOS-Tenant-Id': config.tenantId,
    'X-AgentOS-Agent-Id': config.agentId,
    'X-AgentOS-Agent-Version': config.agentVersion,
    'X-LibreChat-User-Id': config.userId,
    'X-LibreChat-User-Role': config.userRole,
    'X-AgentOS-Conversation-Id': config.conversationId,
  };
}

/** The operator-managed MCP endpoint is the only allowed upload destination. */
export function validateSubmitEndpoint(endpoint: string): URL {
  const url = new URL(endpoint);
  if (
    !['http:', 'https:'].includes(url.protocol) ||
    url.username ||
    url.password ||
    url.pathname !== '/mcp' ||
    url.search ||
    url.hash
  ) {
    throw new Error('Submit requires an operator-managed HTTP MCP endpoint');
  }
  url.pathname = '/v1/attachments';
  return url;
}

function attachmentURL(endpoint: string): URL {
  const url = validateSubmitEndpoint(endpoint);
  url.pathname = '/v1/attachments';
  return url;
}

export function validateSubmitUpload(upload: Omit<SubmitUpload, 'open'>): void {
  if (
    !upload.fileId ||
    !upload.filename ||
    /[\\/]/.test(upload.filename) ||
    [...upload.filename].some((character) => character.charCodeAt(0) < 32)
  ) {
    throw new Error('Submit requires a stored file identifier and a plain filename');
  }
  if (upload.contentType !== 'application/pdf' || !/\.pdf$/i.test(upload.filename)) {
    throw new Error('Submit currently accepts source PDFs only; Excel workbooks are outputs');
  }
  if (
    !Number.isSafeInteger(upload.contentLength) ||
    upload.contentLength <= 0 ||
    upload.contentLength > SUBMIT_MAX_BYTES
  ) {
    throw new Error('Submit PDF must be between 1 byte and 20 MiB');
  }
}

async function readPDF(upload: SubmitUpload): Promise<Buffer> {
  const stream = await upload.open();
  const chunks: Buffer[] = [];
  let size = 0;
  try {
    for await (const chunk of stream) {
      const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
      size += bytes.length;
      if (size > upload.contentLength || size > SUBMIT_MAX_BYTES) {
        throw new Error('Submit file exceeded its stored size');
      }
      chunks.push(bytes);
    }
  } finally {
    stream.destroy();
  }
  const buffer = Buffer.concat(chunks);
  if (size !== upload.contentLength || buffer.subarray(0, 5).toString('ascii') !== '%PDF-') {
    throw new Error('Submit file is incomplete or is not a PDF');
  }
  return buffer;
}

/** Stages a PDF only. The Agent must subsequently call submit_flow.attach_file. */
export async function stageSubmitFile(
  config: SubmitBridgeConfig,
  upload: SubmitUpload,
): Promise<SubmitAttachment> {
  validateSubmitUpload(upload);
  const headers = submitHeaders(config);
  const url = attachmentURL(config.endpoint);
  const bytes = await readPDF(upload);
  const digest = createHash('sha256').update(bytes).digest('hex');
  const key = createHash('sha256')
    .update(
      JSON.stringify([
        config.tenantId,
        config.userId,
        config.conversationId,
        config.agentId,
        config.agentVersion,
        upload.fileId,
        upload.filename,
        digest,
      ]),
    )
    .digest('hex');
  const form = new FormData();
  form.append(
    'file',
    new Blob([new Uint8Array(bytes)], { type: 'application/pdf' }),
    upload.filename,
  );
  const response = await fetch(url, {
    method: 'POST',
    headers: { ...headers, 'Idempotency-Key': key },
    body: form,
    redirect: 'error',
    signal: AbortSignal.timeout(60_000),
  });
  if (!response.ok) {
    await response.body?.cancel();
    throw new Error(`Submit attachment upload failed (${response.status}); retry the message`);
  }
  const attachment = attachmentSchema.parse(await response.json());
  if (attachment.size !== bytes.length || attachment.sha256 !== digest) {
    throw new Error('Submit attachment integrity verification failed');
  }
  return attachment;
}
