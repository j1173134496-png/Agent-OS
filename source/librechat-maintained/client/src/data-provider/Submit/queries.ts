import { useMutation, useQuery } from '@tanstack/react-query';
import { dataService, QueryKeys, MutationKeys } from 'librechat-data-provider';
import type { SubmitTaskRef } from 'librechat-data-provider';

export const useSubmitTask = (task: SubmitTaskRef, enabled: boolean) =>
  useQuery(
    [QueryKeys.submitTask, task.agentId, task.conversationId, task.taskId],
    () => dataService.getSubmitTask(task),
    {
      enabled,
      retry: false,
      refetchInterval: (data) =>
        data && ['completed', 'failed'].includes(data.task.status) ? false : 8000,
      refetchIntervalInBackground: false,
    },
  );

export const useSubmitDownload = (task: SubmitTaskRef) =>
  useMutation(
    [MutationKeys.submitDownload, task.agentId, task.conversationId, task.taskId],
    (artifactId: string) => dataService.getSubmitArtifact(task, artifactId),
  );
