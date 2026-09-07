const mongoose = require('mongoose');
const { logger } = require('@librechat/data-schemas');
const { Constants } = require('librechat-data-provider');
const { mergeAppTools, getAppConfig } = require('./Config');
const { createMCPServersRegistry, createMCPManager } = require('~/config');

const parseRequiredMcpTools = (rawValue) => {
  if (rawValue == null || rawValue.trim() === '') return {};
  const required = {};
  for (const entry of rawValue.split(',')) {
    const [serverName, countValue] = entry.split('=', 2).map((part) => part.trim());
    const count = Number.parseInt(countValue, 10);
    if (!serverName || !Number.isInteger(count) || count < 1) {
      throw new Error(
        'MCP_REQUIRED_TOOLS must use comma-separated server=count entries with positive counts.',
      );
    }
    required[serverName] = count;
  }
  return required;
};

const assertRequiredMcpTools = (mcpServers, mcpTools) => {
  const required = parseRequiredMcpTools(process.env.MCP_REQUIRED_TOOLS);
  for (const [serverName, expectedCount] of Object.entries(required)) {
    if (!Object.prototype.hasOwnProperty.call(mcpServers, serverName)) continue;
    const suffix = `${Constants.mcp_delimiter}${serverName}`;
    const actualCount = Object.keys(mcpTools).filter((toolName) => toolName.endsWith(suffix)).length;
    if (actualCount !== expectedCount) {
      throw new Error(
        `[MCP] Required server "${serverName}" discovered ${actualCount} tools; expected ${expectedCount}. Refusing startup readiness.`,
      );
    }
  }
};

/**
 * Resolves the current request's effective MCP allowlists from the merged (tenant-scoped)
 * config. The registry calls this per inspection/connection so admin-panel `mcpSettings`
 * overrides are honored without a restart. Tenant comes from the ALS context inside
 * `getAppConfig`; `userId`/`role` pick up user/role-scoped overrides when an actor exists.
 * @param {{ userId?: string, role?: string }} [ctx]
 */
async function resolveMCPAllowlists(ctx) {
  const appConfig = await getAppConfig({ role: ctx?.role, userId: ctx?.userId });
  return {
    allowedDomains: appConfig?.mcpSettings?.allowedDomains,
    allowedAddresses: appConfig?.mcpSettings?.allowedAddresses,
  };
}

/**
 * Initialize MCP servers
 */
async function initializeMCPs() {
  const appConfig = await getAppConfig({ baseOnly: true });
  const mcpServers = appConfig.mcpConfig;

  try {
    createMCPServersRegistry(
      mongoose,
      appConfig?.mcpSettings?.allowedDomains,
      appConfig?.mcpSettings?.allowedAddresses,
      resolveMCPAllowlists,
    );
  } catch (error) {
    logger.error('[MCP] Failed to initialize MCPServersRegistry:', error);
    throw error;
  }

  try {
    const mcpManager = await createMCPManager(mcpServers || {});

    if (mcpServers && Object.keys(mcpServers).length > 0) {
      const mcpTools = (await mcpManager.getAppToolFunctions()) || {};
      assertRequiredMcpTools(mcpServers, mcpTools);
      await mergeAppTools(mcpTools);
      const serverCount = Object.keys(mcpServers).length;
      const toolCount = Object.keys(mcpTools).length;
      logger.info(
        `[MCP] Initialized with ${serverCount} configured ${serverCount === 1 ? 'server' : 'servers'} and ${toolCount} ${toolCount === 1 ? 'tool' : 'tools'}.`,
      );
    } else {
      logger.debug('[MCP] No servers configured. MCPManager ready for UI-based servers.');
    }
  } catch (error) {
    logger.error('[MCP] Failed to initialize MCPManager:', error);
    throw error;
  }
}

module.exports = initializeMCPs;
