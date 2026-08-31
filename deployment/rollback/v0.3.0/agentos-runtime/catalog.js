const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const mongoose = require('mongoose');
const { getConvo } = require('~/models');

const CATALOG_PATH = process.env.AGENTOS_PLUGIN_CATALOG_PATH || '/app/agentos/catalog.json';
const SKILLS_PATH = process.env.AGENTOS_PLUGIN_SKILLS_PATH || '/app/agentos/runtime/skills';
const ID_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const TOOL_PATTERN = /^[a-zA-Z0-9_.-]+$/;
const MODEL_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:-]*$/;
const MAX_SKILL_BYTES = 16 * 1024;
const MAX_PLUGIN_ID_LENGTH = 64;
const SUPPORTED_TOOLS = new Set(['agentos_demo', 'image_gen_oai', 'image_edit_oai']);
const RISK_LEVELS = new Set(['read-only', 'controlled-write-local', 'controlled-write-remote']);
const CONFIRMATION_POLICIES = new Set(['none', 'business-review', 'explicit-user-confirmation']);
const REQUIRED_FIELDS = [
  'id',
  'version',
  'name',
  'description',
  'icon',
  'riskLevel',
  'skillIds',
  'mcpServerIds',
  'allowedTools',
  'allowedRoles',
  'confirmationPolicy',
  'enabled',
];

class AgentOSRuntimeError extends Error {
  constructor(code, message, status = 400) {
    super(message);
    this.name = 'AgentOSRuntimeError';
    this.code = code;
    this.status = status;
  }
}

let catalogCache;
let indexPromise;

function exactFields(value, fields, label) {
  const allowed = new Set(fields);
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) {
      throw new AgentOSRuntimeError('CATALOG_INVALID', `${label} contains unsupported field: ${key}`, 500);
    }
  }
}

function validateStringList(value, label, pattern = ID_PATTERN, max = 64, min = 0) {
  if (!Array.isArray(value) || value.length < min || value.length > max) {
    throw new AgentOSRuntimeError('CATALOG_INVALID', `${label} must be an array`, 500);
  }
  const unique = new Set();
  for (const item of value) {
    if (typeof item !== 'string' || !pattern.test(item) || unique.has(item)) {
      throw new AgentOSRuntimeError('CATALOG_INVALID', `${label} contains an invalid or duplicate value`, 500);
    }
    unique.add(item);
  }
}

function validateManifest(manifest, index) {
  const label = `plugins[${index}]`;
  if (!manifest || typeof manifest !== 'object' || Array.isArray(manifest)) {
    throw new AgentOSRuntimeError('CATALOG_INVALID', `${label} must be an object`, 500);
  }
  exactFields(manifest, [...REQUIRED_FIELDS, 'modelType', 'models', 'defaultModel'], label);
  for (const field of REQUIRED_FIELDS) {
    if (!Object.hasOwn(manifest, field)) {
      throw new AgentOSRuntimeError('CATALOG_INVALID', `${label} is missing ${field}`, 500);
    }
  }
  if (
    typeof manifest.id !== 'string' ||
    !ID_PATTERN.test(manifest.id) ||
    manifest.id.length < 2 ||
    manifest.id.length > MAX_PLUGIN_ID_LENGTH ||
    typeof manifest.version !== 'string' ||
    !/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(manifest.version)
  ) {
    throw new AgentOSRuntimeError('CATALOG_INVALID', `${label} has an invalid id or version`, 500);
  }
  if (typeof manifest.name !== 'string' || manifest.name.length === 0 || manifest.name.length > 80) {
    throw new AgentOSRuntimeError('CATALOG_INVALID', `${label}.name is invalid`, 500);
  }
  if (typeof manifest.description !== 'string' || manifest.description.length === 0 || manifest.description.length > 500) {
    throw new AgentOSRuntimeError('CATALOG_INVALID', `${label}.description is invalid`, 500);
  }
  if (typeof manifest.icon !== 'string' || manifest.icon.length === 0 || manifest.icon.length > 300) {
    throw new AgentOSRuntimeError('CATALOG_INVALID', `${label}.icon is invalid`, 500);
  }
  if (!RISK_LEVELS.has(manifest.riskLevel) || !CONFIRMATION_POLICIES.has(manifest.confirmationPolicy)) {
    throw new AgentOSRuntimeError('CATALOG_INVALID', `${label} has an invalid risk or confirmation policy`, 500);
  }
  validateStringList(manifest.skillIds, `${label}.skillIds`, ID_PATTERN, 32);
  validateStringList(manifest.mcpServerIds, `${label}.mcpServerIds`, ID_PATTERN, 32);
  validateStringList(manifest.allowedTools, `${label}.allowedTools`, TOOL_PATTERN);
  for (const tool of manifest.allowedTools) {
    if (!SUPPORTED_TOOLS.has(tool)) {
      throw new AgentOSRuntimeError('CATALOG_INVALID', `${label} requests unsupported tool: ${tool}`, 500);
    }
  }
  validateStringList(manifest.allowedRoles, `${label}.allowedRoles`, /^[a-z0-9_-]+$/, 32, 1);
  if (typeof manifest.enabled !== 'boolean') {
    throw new AgentOSRuntimeError('CATALOG_INVALID', `${label}.enabled must be boolean`, 500);
  }
  if (
    manifest.modelType !== undefined &&
    (typeof manifest.modelType !== 'string' || !['text', 'image', 'other'].includes(manifest.modelType))
  ) {
    throw new AgentOSRuntimeError('CATALOG_INVALID', `${label}.modelType is invalid`, 500);
  }
  if (manifest.models !== undefined) {
    validateStringList(manifest.models, `${label}.models`, MODEL_PATTERN, 32, 1);
  }
  if (manifest.defaultModel !== undefined) {
    if (
      typeof manifest.defaultModel !== 'string' ||
      !MODEL_PATTERN.test(manifest.defaultModel) ||
      !Array.isArray(manifest.models) ||
      !manifest.models.includes(manifest.defaultModel)
    ) {
      throw new AgentOSRuntimeError('CATALOG_INVALID', `${label}.defaultModel is invalid`, 500);
    }
  }
  if (manifest.modelType === 'image' && (!Array.isArray(manifest.models) || !manifest.defaultModel)) {
    throw new AgentOSRuntimeError('CATALOG_INVALID', `${label} image model metadata is incomplete`, 500);
  }
  return manifest;
}

function loadCatalog() {
  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(path.resolve(CATALOG_PATH), 'utf8'));
  } catch (error) {
    throw new AgentOSRuntimeError('CATALOG_UNAVAILABLE', `Unable to load plugin catalog: ${error.message}`, 500);
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new AgentOSRuntimeError('CATALOG_INVALID', 'Plugin catalog must be an object', 500);
  }
  exactFields(parsed, ['schema_version', 'plugins'], 'catalog');
  if (parsed.schema_version !== 'agentos.plugin-catalog.v1' || !Array.isArray(parsed.plugins)) {
    throw new AgentOSRuntimeError('CATALOG_INVALID', 'Unsupported plugin catalog schema', 500);
  }
  const ids = new Set();
  const plugins = parsed.plugins.map((plugin, index) => {
    const validated = validateManifest(plugin, index);
    if (ids.has(validated.id)) {
      throw new AgentOSRuntimeError('CATALOG_INVALID', `Duplicate plugin id: ${validated.id}`, 500);
    }
    ids.add(validated.id);
    return Object.freeze({
      ...validated,
      skillIds: Object.freeze([...validated.skillIds]),
      mcpServerIds: Object.freeze([...validated.mcpServerIds]),
      allowedTools: Object.freeze([...validated.allowedTools]),
      allowedRoles: Object.freeze([...validated.allowedRoles]),
      ...(validated.models ? { models: Object.freeze([...validated.models]) } : {}),
    });
  });
  return Object.freeze({ schema_version: parsed.schema_version, plugins: Object.freeze(plugins) });
}

function getCatalog() {
  if (!catalogCache) {
    catalogCache = loadCatalog();
  }
  return catalogCache;
}

function normalizeRole(role) {
  const normalized = String(role || 'user').toLowerCase().replace(/^role[_-]/, '');
  return normalized || 'user';
}

function getAuthorizedPlugins(user) {
  const role = normalizeRole(user?.role);
  return getCatalog().plugins.filter(
    (plugin) => plugin.enabled && plugin.allowedRoles.includes(role),
  );
}

function getPluginMap(user) {
  return new Map(getAuthorizedPlugins(user).map((plugin) => [plugin.id, plugin]));
}

function validateConversationId(value) {
  if (typeof value !== 'string' || value.length < 1 || value.length > 128 || !/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new AgentOSRuntimeError('INVALID_CONVERSATION', 'conversation_id is invalid', 400);
  }
  return value;
}

function validateSelectedPluginIds(value, user) {
  if (!Array.isArray(value) || value.length > 16) {
    throw new AgentOSRuntimeError('INVALID_PLUGIN_SELECTION', 'selected_plugin_ids must be an array with at most 16 entries', 400);
  }
  const pluginMap = getPluginMap(user);
  const selected = [];
  const seen = new Set();
  for (const pluginId of value) {
    if (typeof pluginId !== 'string' || !ID_PATTERN.test(pluginId) || seen.has(pluginId)) {
      throw new AgentOSRuntimeError('INVALID_PLUGIN_SELECTION', 'selected_plugin_ids contains an invalid or duplicate id', 400);
    }
    if (!pluginMap.has(pluginId)) {
      throw new AgentOSRuntimeError('PLUGIN_FORBIDDEN', `Plugin is not available: ${pluginId}`, 403);
    }
    seen.add(pluginId);
    selected.push(pluginId);
  }
  return selected;
}

async function assertConversationAccess(userId, conversationId) {
  const id = validateConversationId(conversationId);
  if (id === 'new') {
    return;
  }
  const conversation = await getConvo(userId, id);
  if (!conversation) {
    throw new AgentOSRuntimeError('CONVERSATION_FORBIDDEN', 'Conversation is not available to this user', 403);
  }
}

async function getCollection(name) {
  if (!mongoose.connection?.db) {
    throw new AgentOSRuntimeError('STORAGE_UNAVAILABLE', 'AgentOS storage is not ready', 503);
  }
  if (!indexPromise) {
    indexPromise = Promise.all([
      mongoose.connection.db.collection('agentos_conversation_plugins').createIndex(
        { user_id: 1, conversation_id: 1 },
        { unique: true },
      ),
      mongoose.connection.db.collection('agentos_audit_events').createIndex({ user_id: 1, created_at: -1 }),
    ]).catch((error) => {
      indexPromise = undefined;
      throw error;
    });
  }
  await indexPromise;
  return mongoose.connection.db.collection(name);
}

async function readSelection(userId, conversationId) {
  const id = validateConversationId(conversationId);
  const collection = await getCollection('agentos_conversation_plugins');
  const record = await collection.findOne({ user_id: String(userId), conversation_id: id });
  return record?.selected_plugin_ids ?? [];
}

async function saveSelection(user, conversationId, selectedPluginIds) {
  const id = validateConversationId(conversationId);
  await assertConversationAccess(user.id, id);
  const selected = validateSelectedPluginIds(selectedPluginIds, user);
  const collection = await getCollection('agentos_conversation_plugins');
  const updatedAt = new Date();
  await collection.updateOne(
    { user_id: String(user.id), conversation_id: id },
    {
      $set: { user_id: String(user.id), conversation_id: id, selected_plugin_ids: selected, updated_at: updatedAt },
    },
    { upsert: true },
  );
  return { conversation_id: id, user_id: String(user.id), selected_plugin_ids: selected, updated_at: updatedAt };
}

async function resolveRequestSelection(req) {
  const conversationId = validateConversationId(req.body?.conversationId || 'new');
  await assertConversationAccess(req.user.id, conversationId);
  const raw = req.body?.agentos_plugin_ids;
  if (raw === undefined) {
    const stored = await readSelection(req.user.id, conversationId);
    return validateSelectedPluginIds(stored, req.user);
  }
  const selected = validateSelectedPluginIds(raw, req.user);
  await saveSelection(req.user, conversationId, selected);
  return selected;
}

function getToolsForPlugins(pluginIds, user) {
  const pluginMap = getPluginMap(user);
  const tools = new Set();
  for (const pluginId of pluginIds) {
    const plugin = pluginMap.get(pluginId);
    if (!plugin) {
      throw new AgentOSRuntimeError('PLUGIN_FORBIDDEN', `Plugin is not available: ${pluginId}`, 403);
    }
    for (const tool of plugin.allowedTools) {
      if (SUPPORTED_TOOLS.has(tool)) {
        tools.add(tool);
      }
    }
  }
  return [...tools];
}

function getSkillsForPlugins(pluginIds, user) {
  const pluginMap = getPluginMap(user);
  const skills = [];
  const seen = new Set();
  const root = path.resolve(SKILLS_PATH);

  for (const pluginId of pluginIds) {
    const plugin = pluginMap.get(pluginId);
    if (!plugin) {
      throw new AgentOSRuntimeError('PLUGIN_FORBIDDEN', `Plugin is not available: ${pluginId}`, 403);
    }
    for (const skillId of plugin.skillIds) {
      if (seen.has(skillId)) {
        continue;
      }
      seen.add(skillId);
      const skillPath = path.resolve(root, `${skillId}.md`);
      if (skillPath !== root && !skillPath.startsWith(`${root}${path.sep}`)) {
        throw new AgentOSRuntimeError('SKILL_INVALID', `Skill path is invalid: ${skillId}`, 500);
      }
      let content;
      try {
        const stat = fs.statSync(skillPath);
        if (!stat.isFile() || stat.size > MAX_SKILL_BYTES) {
          throw new Error('skill file is missing, not a regular file, or too large');
        }
        content = fs.readFileSync(skillPath, 'utf8').trim();
      } catch (error) {
        throw new AgentOSRuntimeError(
          'SKILL_UNAVAILABLE',
          `Unable to load selected plugin skill ${skillId}: ${error.message}`,
          500,
        );
      }
      if (!content) {
        throw new AgentOSRuntimeError('SKILL_INVALID', `Selected plugin skill is empty: ${skillId}`, 500);
      }
      skills.push(Object.freeze({ id: skillId, pluginId, content }));
    }
  }
  return Object.freeze(skills);
}

async function recordAuditEvent(event) {
  const collection = await getCollection('agentos_audit_events');
  const requestId = event.request_id || `req_${crypto.randomUUID()}`;
  const record = {
    request_id: requestId,
    user_id: String(event.user_id),
    conversation_id: validateConversationId(event.conversation_id || 'new'),
    plugin_id: String(event.plugin_id),
    operation: String(event.operation),
    status: String(event.status),
    created_at: new Date(),
  };
  await collection.insertOne(record);
  return `audit_${record._id.toString()}`;
}

function createRequestId() {
  return `req_${crypto.randomUUID()}`;
}

module.exports = {
  AgentOSRuntimeError,
  createRequestId,
  getCatalog,
  getAuthorizedPlugins,
  getPluginMap,
  validateConversationId,
  validateSelectedPluginIds,
  assertConversationAccess,
  readSelection,
  saveSelection,
  resolveRequestSelection,
  getToolsForPlugins,
  getSkillsForPlugins,
  recordAuditEvent,
};
