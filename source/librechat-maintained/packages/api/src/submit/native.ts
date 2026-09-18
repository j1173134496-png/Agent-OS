import type { MCPOptions } from 'librechat-data-provider';
import type { ServerRequest } from '~/types';
import { resolveSubmitConfig } from './config';
import { getThreadData } from '~/utils/message';
import { primeSubmitAttachments } from './context';

type BrokerDeps = Parameters<typeof primeSubmitAttachments>[0]['deps'];

/** Adds only broker-issued IDs to the already-authorized native Agent run. */
export async function primeNativeSubmit({
  req,
  agentId,
  fileIds,
  options,
  canUseMCP,
  deps,
}: {
  req: ServerRequest;
  agentId: string;
  fileIds: string[];
  options?: MCPOptions & { dbId?: string };
  canUseMCP: boolean;
  deps: BrokerDeps & {
    getMessages: (
      filter: { conversationId: string; user: string },
      fields: string,
    ) => Promise<Parameters<typeof getThreadData>[0]>;
  };
}): Promise<string> {
  if (
    !req.user?.id ||
    !req.user.role ||
    !req.body.conversationId ||
    !canUseMCP ||
    !options ||
    options.dbId
  ) {
    throw new Error(
      'Submit requires an authenticated conversation and operator-managed MCP access',
    );
  }
  const config = resolveSubmitConfig({
    user: req.user,
    conversationId: req.body.conversationId,
    agentId,
    options,
  });
  const parent = req.body.parentMessageId;
  const messages = parent
    ? await deps.getMessages(
        { conversationId: req.body.conversationId, user: req.user.id },
        'messageId parentMessageId files',
      )
    : [];
  const ids = [...new Set([...getThreadData(messages, parent).fileIds, ...fileIds])];
  return primeSubmitAttachments({
    req,
    fileIds: ids,
    config,
    deps,
  });
}
