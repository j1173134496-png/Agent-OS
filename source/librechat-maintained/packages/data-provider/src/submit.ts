import { z } from 'zod';

export const submitTaskSchema = z.object({
  task_id: z.string().regex(/^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$/),
  site_key: z.string(),
  site_name: z.string().nullish(),
  month: z.string().regex(/^20\d{2}-(0[1-9]|1[0-2])$/),
  status: z.string().max(64),
  received_count: z.number().int().nonnegative().nullish(),
  required_count: z.number().int().nonnegative().nullish(),
  missing_roles: z.array(z.string()).default([]),
});
export const submitArtifactSchema = z.object({
  artifact_id: z.string().regex(/^art_[A-Za-z0-9_-]{16,96}$/),
  file_name: z.string().min(1).max(255),
  kind: z.string(),
  role: z.string(),
  size: z
    .number()
    .int()
    .nonnegative()
    .max(50 * 1024 * 1024),
  sha256: z.string().regex(/^[a-f0-9]{64}$/),
  status: z.string(),
});
export const submitOutputsSchema = z.object({
  task_id: z.string(),
  artifacts: z.array(submitArtifactSchema).max(50),
});
export type SubmitTask = z.infer<typeof submitTaskSchema>;
export type SubmitArtifact = z.infer<typeof submitArtifactSchema>;
export type SubmitSnapshot = { task: SubmitTask; artifacts: SubmitArtifact[] };
export type SubmitTaskRef = { agentId: string; conversationId: string; taskId: string };
