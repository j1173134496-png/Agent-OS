import { useContext, useMemo, useState } from 'react';
import { z } from 'zod';
import { Download, RefreshCw, LoaderCircle } from 'lucide-react';
import type { SubmitArtifact } from 'librechat-data-provider';
import { useSubmitTask, useSubmitDownload } from '~/data-provider';
import { ChatContext } from '~/Providers/ChatContext';
import { triggerDownload } from '~/utils';
import { useLocalize } from '~/hooks';

const taskRefSchema = z.object({ task_id: z.string().regex(/^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$/) });
const statusKeys = {
  collecting_files: 'com_ui_submit_collecting',
  ready_to_run: 'com_ui_submit_ready',
  running: 'com_ui_submit_running',
  processing: 'com_ui_submit_running',
  need_review: 'com_ui_submit_review',
  completed: 'com_ui_submit_completed',
  failed: 'com_ui_failed',
} as const;

export function submitTaskId(output?: string | null): string {
  try {
    const result = taskRefSchema.safeParse(JSON.parse(output ?? ''));
    return result.success ? result.data.task_id : '';
  } catch {
    return '';
  }
}

export default function SubmitTask({ output }: { output?: string | null }) {
  const localize = useLocalize();
  const chat = useContext(ChatContext);
  const [downloadError, setDownloadError] = useState(false);
  const taskId = useMemo(() => submitTaskId(output), [output]);
  const reference = {
    agentId: chat?.conversation?.agent_id ?? '',
    conversationId: chat?.conversation?.conversationId ?? '',
    taskId,
  };
  const enabled = Boolean(reference.agentId && reference.conversationId && taskId);
  const query = useSubmitTask(reference, enabled);
  const download = useSubmitDownload(reference);
  if (!enabled) return null;

  const saveArtifact = async (artifact: SubmitArtifact) => {
    setDownloadError(false);
    try {
      const result = await download.mutateAsync(artifact.artifact_id);
      const target = URL.createObjectURL(result.data);
      triggerDownload(target, artifact.file_name);
      window.setTimeout(() => URL.revokeObjectURL(target), 0);
    } catch {
      setDownloadError(true);
    }
  };
  const task = query.data?.task;
  const statusKey = task && statusKeys[task.status as keyof typeof statusKeys];
  return (
    <section
      className="my-3 min-w-0 border-y border-border-light py-3 text-sm"
      aria-label={localize('com_ui_submit_task')}
    >
      <div className="flex min-h-8 items-center justify-between gap-3">
        <div className="min-w-0 break-words font-medium">
          {task
            ? `${task.site_name || task.site_key} · ${task.month}`
            : localize('com_ui_submit_task')}
        </div>
        <button
          type="button"
          className="flex h-8 w-8 shrink-0 items-center justify-center rounded hover:bg-surface-hover"
          title={localize('com_ui_retry')}
          aria-label={localize('com_ui_retry')}
          disabled={query.isFetching}
          onClick={() => void query.refetch()}
        >
          <RefreshCw
            className={`h-4 w-4 ${query.isFetching ? 'animate-spin' : ''}`}
            aria-hidden="true"
          />
        </button>
      </div>
      <p role="status" className="break-words text-text-secondary">
        {query.isError
          ? localize('com_ui_submit_unavailable')
          : !task
            ? localize('com_ui_loading')
            : localize(statusKey || 'com_ui_submit_unknown')}
        {task?.status === 'collecting_files' &&
          task.received_count != null &&
          ` (${task.received_count}/${task.required_count ?? 3})`}
      </p>
      <ul className="mt-2 divide-y divide-border-light">
        {query.data?.artifacts.map((artifact) => (
          <li key={artifact.artifact_id} className="flex min-h-10 items-center gap-3 py-1">
            <span className="min-w-0 flex-1 break-all">{artifact.file_name}</span>
            <button
              type="button"
              className="flex h-8 w-8 shrink-0 items-center justify-center rounded hover:bg-surface-hover"
              title={localize('com_ui_download')}
              aria-label={`${localize('com_ui_download')} ${artifact.file_name}`}
              disabled={download.isLoading}
              onClick={() => void saveArtifact(artifact)}
            >
              {download.isLoading ? (
                <LoaderCircle className="h-4 w-4 animate-spin" aria-hidden="true" />
              ) : (
                <Download className="h-4 w-4" aria-hidden="true" />
              )}
            </button>
          </li>
        ))}
      </ul>
      {downloadError && (
        <p role="alert" className="text-text-error mt-2">
          {localize('com_ui_download_error')}
        </p>
      )}
    </section>
  );
}
