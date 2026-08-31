const { Tool } = require('@librechat/agents/langchain/tools');
const {
  AgentOSRuntimeError,
  createRequestId,
  recordAuditEvent,
} = require('./catalog');

const demoSchema = {
  type: 'object',
  additionalProperties: false,
  properties: {
    operation: {
      type: 'string',
      enum: ['health_check', 'describe_capabilities', 'echo'],
      description: 'A safe, read-only demonstration operation.',
    },
    payload: {
      type: 'string',
      maxLength: 500,
      description: 'Optional short text payload. Only used by echo.',
    },
  },
  required: ['operation'],
};

function validateArguments(args) {
  if (!args || typeof args !== 'object' || Array.isArray(args)) {
    throw new AgentOSRuntimeError('INVALID_ARGUMENT', 'Demo tool arguments must be an object', 400);
  }
  const keys = Object.keys(args);
  if (keys.some((key) => !['operation', 'payload'].includes(key))) {
    throw new AgentOSRuntimeError('INVALID_ARGUMENT', 'Demo tool received an unsupported field', 400);
  }
  if (!['health_check', 'describe_capabilities', 'echo'].includes(args.operation)) {
    throw new AgentOSRuntimeError('INVALID_ARGUMENT', 'Demo operation is not allowed', 400);
  }
  if (args.payload !== undefined && (typeof args.payload !== 'string' || args.payload.length > 500)) {
    throw new AgentOSRuntimeError('INVALID_ARGUMENT', 'Demo payload must be at most 500 characters', 400);
  }
  if (args.operation !== 'echo' && args.payload !== undefined) {
    throw new AgentOSRuntimeError('INVALID_ARGUMENT', 'payload is only allowed for echo', 400);
  }
}

async function runDemoRequest({ userId, conversationId, req, args }) {
  const requestId = createRequestId();
  let status = 'completed';
  let error = null;
  let summary = 'AgentOS Demo Tool completed a read-only operation.';
  let data;

  try {
    validateArguments(args);
    if (args.operation === 'health_check') {
      data = { service: 'AgentOS', status: 'ok', side_effects: false };
      summary = 'AgentOS Demo Tool is healthy. No side effects were performed.';
    } else if (args.operation === 'describe_capabilities') {
      data = {
        capabilities: ['catalog', 'conversation_plugin_selection', 'server_capability_gate'],
        blocked: ['shell', 'arbitrary_path', 'arbitrary_url', 'free_command'],
      };
      summary = 'AgentOS Demo Tool returned the V0.3 capability boundary.';
    } else {
      data = { echoed: args.payload || '' };
      summary = 'AgentOS Demo Tool echoed the supplied text without side effects.';
    }
  } catch (toolError) {
    status = 'rejected';
    error = { code: toolError.code || 'INVALID_ARGUMENT', message: toolError.message };
    summary = 'AgentOS Demo Tool rejected the request.';
  }

  const auditRef = await recordAuditEvent({
    request_id: requestId,
    user_id: userId,
    conversation_id: conversationId || req?.body?.conversationId || 'new',
    plugin_id: 'agentos-demo',
    operation: args?.operation || 'invalid',
    status,
  });

  return {
    request_id: requestId,
    plugin_id: 'agentos-demo',
    operation: args?.operation || 'invalid',
    status,
    summary,
    task_id: null,
    run_id: null,
    next_action: null,
    review: null,
    artifacts: [],
    data: data || null,
    error,
    audit_ref: auditRef,
  };
}

class AgentOSDemo extends Tool {
  constructor(fields = {}) {
    super();
    this.name = 'agentos_demo';
    this.description =
      'AgentOS V0.3 read-only demo capability. Use only health_check, describe_capabilities, or echo. Never request shell, paths, URLs, or commands.';
    this.schema = demoSchema;
    this.userId = fields.userId;
    this.req = fields.req;
  }

  async _call(args) {
    const result = await runDemoRequest({
      userId: this.userId || this.req?.user?.id,
      conversationId: this.req?.body?.conversationId,
      req: this.req,
      args,
    });
    return JSON.stringify(result);
  }
}

AgentOSDemo.jsonSchema = demoSchema;
AgentOSDemo.runDemoRequest = runDemoRequest;

module.exports = AgentOSDemo;
