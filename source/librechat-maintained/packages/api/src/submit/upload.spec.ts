import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { mkdtemp, writeFile, rm, readFile } from 'node:fs/promises';
import { preserveSubmitPDF } from './upload';

describe('Submit source preservation', () => {
  let directory: string;
  const pdf = Buffer.from('%PDF-1.7\nsource-preservation');
  beforeAll(async () => {
    directory = await mkdtemp(join(tmpdir(), 'submit-upload-test-'));
    await writeFile(join(directory, 'source.pdf'), pdf);
  });
  afterAll(async () => {
    await rm(directory, { recursive: true, force: true });
  });
  const params = () => ({
    agentId: 'agent_smart_submit_v1',
    messageAttachment: true,
    resource: 'context',
    fileId: 'file-1',
    file: {
      path: join(directory, 'source.pdf'),
      originalname: 'source.pdf',
      mimetype: 'application/pdf',
      size: pdf.length,
    },
  });
  test('preserves bytes for native Submit message attachments', async () => {
    await expect(preserveSubmitPDF(params())).resolves.toBe(true);
    expect(await readFile(join(directory, 'source.pdf'))).toEqual(pdf);
  });
  test.each([
    { agentId: 'unrelated-agent' },
    { messageAttachment: false },
    { resource: 'file_search' },
  ])('leaves other uploads unchanged: %j', async (change) => {
    await expect(preserveSubmitPDF({ ...params(), ...change })).resolves.toBe(false);
  });
  test('rejects mismatched stored length', async () => {
    const input = params();
    input.file.size += 1;
    await expect(preserveSubmitPDF(input)).rejects.toThrow('intact PDF');
  });
});
