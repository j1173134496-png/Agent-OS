import { open } from 'node:fs/promises';
import { validateSubmitUpload } from './bridge';

/** Preserve business source bytes instead of running the generic text/OCR upload path. */
export async function preserveSubmitPDF({
  agentId,
  messageAttachment,
  resource,
  file,
  fileId,
}: {
  agentId?: string;
  messageAttachment: boolean;
  resource?: string;
  file: { path: string; originalname: string; mimetype: string; size: number };
  fileId: string;
}): Promise<boolean> {
  if (
    agentId !== (process.env.SUBMIT_PLATFORM_AGENT_ID || 'agent_smart_submit_v1') ||
    !messageAttachment ||
    resource !== 'context'
  )
    return false;
  validateSubmitUpload({
    fileId,
    filename: file.originalname,
    contentType: file.mimetype,
    contentLength: file.size,
  });
  const handle = await open(file.path, 'r');
  try {
    const info = await handle.stat();
    const magic = Buffer.alloc(5);
    const { bytesRead } = await handle.read(magic, 0, 5, 0);
    if (
      !info.isFile() ||
      info.size !== file.size ||
      bytesRead !== 5 ||
      magic.toString('ascii') !== '%PDF-'
    ) {
      throw new Error('Submit source must be an intact PDF');
    }
  } finally {
    await handle.close();
  }
  return true;
}
