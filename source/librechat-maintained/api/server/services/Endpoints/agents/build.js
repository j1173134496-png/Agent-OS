const { logger } = require('@librechat/data-schemas');
const { loadAgent: loadAgentFn } = require('@librechat/api');
const { isAgentsEndpoint, removeNullishValues, Constants } = require('librechat-data-provider');
const { getMCPServerTools } = require('~/server/services/Config');
const db = require('~/models');

const loadAgent = (params) => loadAgentFn(params, { getAgent: db.getAgent, getMCPServerTools });

const buildOptions = (req, endpoint, parsedBody, endpointType) => {
  const { spec, iconURL, agent_id, chatProjectId, ...model_parameters } = parsedBody;
  const resolvedAgentId = isAgentsEndpoint(endpoint) ? agent_id : Constants.EPHEMERAL_AGENT_ID;
  const agentPromise = loadAgent({
    req,
    spec,
    agent_id: resolvedAgentId,
    endpoint,
    model_parameters,
  })
    .then((agent) => {
      logger.info('[agents] Resolved chat agent', {
        requestEndpoint: endpoint,
        requestedAgentId: agent_id,
        resolvedAgentId,
        requestModel: model_parameters?.model,
        loadedAgent: agent
          ? { id: agent.id, provider: agent.provider, model: agent.model }
          : null,
      });
      return agent;
    })
    .catch((error) => {
      logger.error(`[/agents/:${agent_id}] Error retrieving agent during build options step`, error);
      return undefined;
    });

  /** @type {import('librechat-data-provider').TConversation | undefined} */
  const addedConvo = req.body?.addedConvo;

  return removeNullishValues({
    spec,
    iconURL,
    endpoint,
    agent_id,
    endpointType,
    chatProjectId,
    model_parameters,
    agent: agentPromise,
    addedConvo,
  });
};

module.exports = { buildOptions };
