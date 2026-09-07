import {
  getDefaultReasoningLevel,
  getReasoningDisplayLabel,
  getNextReasoningLevel,
  getSupportedReasoningLevels,
} from '../agentosReasoning';
import type { TAgentOSReasoningConfig } from 'librechat-data-provider';

const config: TAgentOSReasoningConfig = {
  enabled: true,
  default: 'medium',
  levels: ['low', 'medium', 'high'],
  models: {
    'gpt-5.5': { levels: ['low', 'medium', 'high'] },
    'gpt-5.6-sol': { levels: ['low', 'high'] },
    'gpt-5.6-terra': { levels: [] },
    'gpt-5.6-luna': { levels: ['low', 'medium', 'high'] },
  },
};

const approvedModels = ['gpt-5.6-sol', 'gpt-5.6-terra', 'gpt-5.6-luna', 'gpt-5.5'];

describe('AgentOS reasoning capability matrix', () => {
  it('keeps the approved model capability entries distinct', () => {
    expect(Object.keys(config.models).sort()).toEqual([...approvedModels].sort());
    expect(new Set(approvedModels).size).toBe(approvedModels.length);
  });

  it('returns only the levels verified for a model', () => {
    expect(getSupportedReasoningLevels(config, 'gpt-5.6-sol')).toEqual(['low', 'high']);
    expect(getSupportedReasoningLevels(config, 'gpt-5.6-terra')).toEqual([]);
  });

  it('does not expose levels when the capability contract is disabled', () => {
    expect(getSupportedReasoningLevels({ ...config, enabled: false }, 'gpt-5.5')).toEqual([]);
  });

  it('shows automatic mode when no valid level is selected', () => {
    expect(getReasoningDisplayLabel(config, 'gpt-5.5', null)).toBe('自动');
    expect(getReasoningDisplayLabel(config, 'gpt-5.5', 'high')).toBe('高');
    expect(getReasoningDisplayLabel(config, 'gpt-5.5', 'xhigh')).toBe('自动');
  });

  it('resolves the configured default only from verified levels', () => {
    expect(getDefaultReasoningLevel(config, 'gpt-5.5')).toBe('medium');
    expect(getDefaultReasoningLevel(config, 'gpt-5.6-terra')).toBe('');
  });

  it('preserves a verified selection and falls back for a new model', () => {
    expect(getNextReasoningLevel(config, 'gpt-5.6-sol', 'high')).toBe('high');
    expect(getNextReasoningLevel(config, 'gpt-5.6-sol', 'medium')).toBe('low');
    expect(getNextReasoningLevel(config, 'gpt-5.6-terra', 'high')).toBe('');
  });
});
