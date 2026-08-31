const { logger } = require('@librechat/data-schemas');
const {
  AgentOSRuntimeError,
  resolveRequestSelection,
  getToolsForPlugins,
  getSkillsForPlugins,
} = require('./catalog');

function injectSelectedPluginSkills(agent, skills) {
  if (!skills.length) {
    return;
  }
  const skillText = [
    'The following trusted AgentOS plugin skills are active for this request.',
    'Use only the tools exposed by the capability gate and follow these instructions as operational guidance.',
    ...skills.map((skill) => `Plugin skill ${skill.id}:\n${skill.content}`),
  ].join('\n\n');
  agent.additional_instructions = [agent.additional_instructions || '', skillText]
    .filter(Boolean)
    .join('\n\n');
}

/**
 * Runs after LibreChat builds endpointOption and before the Agent controller.
 * The client can request a selection, but only this server-side gate decides
 * which tool keys reach the Agent runtime.
 */
module.exports = async function agentosCapabilityGate(req, res, next) {
  try {
    const selectedPluginIds = await resolveRequestSelection(req);
    const tools = getToolsForPlugins(selectedPluginIds, req.user);
    const skills = getSkillsForPlugins(selectedPluginIds, req.user);
    const endpointOption = req.body?.endpointOption;
    if (!endpointOption?.agent) {
      throw new AgentOSRuntimeError('AGENT_NOT_AVAILABLE', 'Agent endpoint is not available', 500);
    }

    const agent = await endpointOption.agent;
    if (!agent || typeof agent !== 'object') {
      throw new AgentOSRuntimeError('AGENT_NOT_AVAILABLE', 'Agent endpoint is not available', 500);
    }

    // Strip every client-provided tool list and replace it with the catalog union.
    agent.tools = tools;
    injectSelectedPluginSkills(agent, skills);
    endpointOption.model_parameters = {
      ...(endpointOption.model_parameters || {}),
      tools,
    };
    endpointOption.agent = Promise.resolve(agent);
    req.agentosCapability = {
      selectedPluginIds,
      tools,
      skills: skills.map((skill) => skill.id),
    };
    delete req.body.tools;
    delete req.body.mcpServers;
    return next();
  } catch (error) {
    logger.warn('[AgentOS] Capability gate rejected request', {
      code: error?.code,
      message: error?.message,
      userId: req.user?.id,
      conversationId: req.body?.conversationId,
    });
    const status = Number.isInteger(error?.status) ? error.status : 500;
    return res.status(status).json({
      error: error?.code || 'AGENTOS_CAPABILITY_GATE_ERROR',
      message: error?.message || 'AgentOS capability gate failed',
    });
  }
};
