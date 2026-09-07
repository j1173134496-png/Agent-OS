import type { TAgentOSReasoningConfig } from 'librechat-data-provider';

export type AgentOSReasoningLevel = 'low' | 'medium' | 'high';

export const AGENTOS_REASONING_LABELS: Record<AgentOSReasoningLevel, string> = {
  low: '低',
  medium: '中',
  high: '高',
};

export function getSupportedReasoningLevels(
  config: TAgentOSReasoningConfig | undefined,
  modelId: string,
): AgentOSReasoningLevel[] {
  if (!config?.enabled || !modelId) {
    return [];
  }

  const configuredLevels = config.models?.[modelId]?.levels ?? [];
  const allowedLevels = new Set(config.levels ?? []);
  return configuredLevels.filter(
    (level): level is AgentOSReasoningLevel => allowedLevels.has(level),
  );
}

export function getReasoningDisplayLabel(
  config: TAgentOSReasoningConfig | undefined,
  modelId: string,
  value?: string | null,
): string {
  const levels = getSupportedReasoningLevels(config, modelId);
  if (value && levels.includes(value as AgentOSReasoningLevel)) {
    return AGENTOS_REASONING_LABELS[value as AgentOSReasoningLevel];
  }
  return '自动';
}

export function getDefaultReasoningLevel(
  config: TAgentOSReasoningConfig | undefined,
  modelId: string,
): AgentOSReasoningLevel | '' {
  const levels = getSupportedReasoningLevels(config, modelId);
  const configuredDefault = config?.default;
  return configuredDefault && levels.includes(configuredDefault)
    ? configuredDefault
    : (levels[0] ?? '');
}

export function getNextReasoningLevel(
  config: TAgentOSReasoningConfig | undefined,
  modelId: string,
  currentValue?: string | null,
): AgentOSReasoningLevel | '' {
  const levels = getSupportedReasoningLevels(config, modelId);
  if (currentValue && levels.includes(currentValue as AgentOSReasoningLevel)) {
    return currentValue as AgentOSReasoningLevel;
  }
  return getDefaultReasoningLevel(config, modelId);
}
