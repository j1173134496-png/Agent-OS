const express = require('express');
const { logger } = require('@librechat/data-schemas');
const requireJwtAuth = require('/app/api/server/middleware/requireJwtAuth');
const AgentOSDemo = require('./AgentOSDemo');
const {
  AgentOSRuntimeError,
  getAuthorizedPlugins,
  getPluginMap,
  validateConversationId,
  validateSelectedPluginIds,
  assertConversationAccess,
  readSelection,
  saveSelection,
  getToolsForPlugins,
  getSkillsForPlugins,
} = require('./catalog');

const router = express.Router();
router.use(requireJwtAuth);

function sendRuntimeError(res, error) {
  const status = Number.isInteger(error?.status) ? error.status : 500;
  return res.status(status).json({
    error: error?.code || 'AGENTOS_RUNTIME_ERROR',
    message: error?.message || 'AgentOS runtime request failed',
  });
}

router.get('/catalog', (req, res) => {
  try {
    const plugins = getAuthorizedPlugins(req.user).map((plugin) => ({ ...plugin }));
    return res.json({ schema_version: 'agentos.plugin-catalog.v1', plugins });
  } catch (error) {
    logger.error('[AgentOS] Failed to load plugin catalog', error);
    return sendRuntimeError(res, error);
  }
});

router.get('/selection', async (req, res) => {
  try {
    if (Array.isArray(req.query.conversation_id) || typeof req.query.conversation_id !== 'string') {
      throw new AgentOSRuntimeError('INVALID_CONVERSATION', 'conversation_id is required', 400);
    }
    const conversationId = validateConversationId(req.query.conversation_id);
    await assertConversationAccess(req.user.id, conversationId);
    const selectedPluginIds = validateSelectedPluginIds(
      await readSelection(req.user.id, conversationId),
      req.user,
    );
    return res.json({
      user_id: String(req.user.id),
      conversation_id: conversationId,
      selected_plugin_ids: selectedPluginIds,
      tools: getToolsForPlugins(selectedPluginIds, req.user),
      skills: getSkillsForPlugins(selectedPluginIds, req.user).map((skill) => skill.id),
    });
  } catch (error) {
    return sendRuntimeError(res, error);
  }
});

router.put('/selection', async (req, res) => {
  try {
    const body = req.body || {};
    const fields = Object.keys(body);
    if (fields.some((field) => !['conversation_id', 'selected_plugin_ids'].includes(field))) {
      throw new AgentOSRuntimeError('INVALID_PLUGIN_SELECTION', 'Unsupported selection field', 400);
    }
    const conversationId = validateConversationId(body.conversation_id);
    const selectedPluginIds = validateSelectedPluginIds(body.selected_plugin_ids, req.user);
    const selection = await saveSelection(req.user, conversationId, selectedPluginIds);
    return res.json({
      ...selection,
      tools: getToolsForPlugins(selectedPluginIds, req.user),
      skills: getSkillsForPlugins(selectedPluginIds, req.user).map((skill) => skill.id),
    });
  } catch (error) {
    return sendRuntimeError(res, error);
  }
});

router.get('/capabilities', async (req, res) => {
  try {
    const conversationId = validateConversationId(req.query.conversation_id || 'new');
    await assertConversationAccess(req.user.id, conversationId);
    const selectedPluginIds = validateSelectedPluginIds(
      await readSelection(req.user.id, conversationId),
      req.user,
    );
    return res.json({
      conversation_id: conversationId,
      selected_plugin_ids: selectedPluginIds,
      tools: getToolsForPlugins(selectedPluginIds, req.user),
      skills: getSkillsForPlugins(selectedPluginIds, req.user).map((skill) => skill.id),
    });
  } catch (error) {
    return sendRuntimeError(res, error);
  }
});

router.post('/plugins/:pluginId/tools/:toolName', async (req, res) => {
  try {
    const { pluginId, toolName } = req.params;
    const conversationId = validateConversationId(req.body?.conversation_id || 'new');
    await assertConversationAccess(req.user.id, conversationId);
    const selectedPluginIds = validateSelectedPluginIds(
      await readSelection(req.user.id, conversationId),
      req.user,
    );
    const plugin = getPluginMap(req.user).get(pluginId);
    if (!plugin || !selectedPluginIds.includes(pluginId)) {
      throw new AgentOSRuntimeError('PLUGIN_NOT_SELECTED', 'Plugin must be selected in this conversation', 403);
    }
    if (!getToolsForPlugins(selectedPluginIds, req.user).includes(toolName)) {
      throw new AgentOSRuntimeError('TOOL_FORBIDDEN', 'Tool is not allowed by the selected plugin', 403);
    }
    if (pluginId !== 'agentos-demo' || toolName !== 'agentos_demo') {
      throw new AgentOSRuntimeError('TOOL_NOT_DIRECTLY_CALLABLE', 'This tool is callable only by the Agent runtime', 405);
    }
    const body = req.body || {};
    if (Object.keys(body).some((field) => !['conversation_id', 'operation', 'payload'].includes(field))) {
      throw new AgentOSRuntimeError('INVALID_ARGUMENT', 'Unsupported tool argument field', 400);
    }
    const result = await AgentOSDemo.runDemoRequest({
      userId: req.user.id,
      conversationId,
      req,
      args: { operation: body.operation, ...(body.payload !== undefined ? { payload: body.payload } : {}) },
    });
    return res.json(result);
  } catch (error) {
    return sendRuntimeError(res, error);
  }
});

module.exports = router;
