import type { IUser } from '@librechat/data-schemas';
import type { MCPOptions } from 'librechat-data-provider';
import type { SubmitBridgeConfig } from './bridge';
import { processMCPEnv } from '~/utils/env';
import { submitHeaders, validateSubmitEndpoint } from './bridge';

export function resolveSubmitConfig({
  user,
  conversationId,
  agentId,
  options,
}: {
  user?: Partial<IUser>;
  conversationId: string;
  agentId: string;
  options?: MCPOptions & { dbId?: string };
}): SubmitBridgeConfig {
  if (!user?.id || !user.role || !conversationId || !options || options.dbId) {
    throw new Error('Submit requires authenticated operator-managed MCP access');
  }
  const platformAgentId = process.env.SUBMIT_PLATFORM_AGENT_ID || 'agent_smart_submit_v1';
  if (agentId !== platformAgentId) {
    throw new Error('Submit Agent binding does not match the managed platform Agent');
  }
  const resolved = processMCPEnv({ options, user, body: { conversationId } });
  const businessAgentId = process.env.SUBMIT_AGENT_ID || 'smart-submit-v1';
  if (
    !('url' in resolved) ||
    !resolved.url ||
    !('headers' in resolved) ||
    !resolved.headers ||
    resolved.headers['X-AgentOS-Agent-Id'] !== businessAgentId
  ) {
    throw new Error('Submit Agent binding does not match the managed MCP configuration');
  }
  const config: SubmitBridgeConfig = {
    endpoint: resolved.url,
    authorization: resolved.headers.Authorization ?? '',
    tenantId: resolved.headers['X-AgentOS-Tenant-Id'] ?? '',
    // `agentId` is the LibreChat platform Agent identity. Submit keeps its
    // independent business binding so existing tasks remain compatible.
    agentId: businessAgentId,
    agentVersion: resolved.headers['X-AgentOS-Agent-Version'] ?? '',
    userId: user.id,
    userRole: user.role,
    conversationId,
  };
  if (user.tenantId != null && user.tenantId !== config.tenantId) {
    throw new Error('Submit tenant binding is invalid');
  }
  submitHeaders(config);
  validateSubmitEndpoint(config.endpoint);
  return config;
}
