import React, { useEffect, useMemo } from 'react';
import { BrainCircuit, Check, ChevronRight, Cpu } from 'lucide-react';
import { VisuallyHidden } from '@ariakit/react';
import { isAgentsEndpoint } from 'librechat-data-provider';
import type { TInterfaceConfig, TModelSpec } from 'librechat-data-provider';
import { useChatContext } from '~/Providers';
import { useLocalize, useSetIndexOptions } from '~/hooks';
import { cn } from '~/utils';
import { CustomMenu as Menu, CustomMenuItem as MenuItem } from './CustomMenu';
import { useModelSelectorContext } from './ModelSelectorContext';
import {
  AGENTOS_REASONING_LABELS,
  getReasoningDisplayLabel,
  getDefaultReasoningLevel,
  getSupportedReasoningLevels,
  getNextReasoningLevel,
  type AgentOSReasoningLevel,
} from './agentosReasoning';

type AgentOSReasoningConfig = NonNullable<TInterfaceConfig['agentosReasoning']>;

interface AgentOSModelSelectorProps {
  reasoning: AgentOSReasoningConfig;
}

function ModelRow({ spec, selected }: { spec: TModelSpec; selected: boolean }) {
  return (
    <>
      <Cpu className="size-4 shrink-0 text-text-secondary" aria-hidden="true" />
      <span className="min-w-0 flex-1 truncate text-left">{spec.label}</span>
      {selected && <Check className="size-4 shrink-0" aria-hidden="true" />}
      {selected && <VisuallyHidden>已选中</VisuallyHidden>}
    </>
  );
}

export default function AgentOSModelSelector({ reasoning }: AgentOSModelSelectorProps) {
  const localize = useLocalize();
  const { conversation } = useChatContext();
  const { setOption } = useSetIndexOptions();
  const {
    modelSpecs,
    selectedValues,
    handleSelectSpec,
    endpoint,
  } = useModelSelectorContext();

  const currentSpec = useMemo(
    () => modelSpecs.find((spec) => spec.name === selectedValues.modelSpec),
    [modelSpecs, selectedValues.modelSpec],
  );
  const currentModelId = currentSpec?.preset.model ?? selectedValues.model ?? '';
  const currentModelLabel = currentSpec?.label ?? selectedValues.model ?? '选择模型';
  const currentReasoning =
    conversation?.reasoning_effort == null
      ? getDefaultReasoningLevel(reasoning, currentModelId)
      : conversation.reasoning_effort;
  const currentReasoningLabel = getReasoningDisplayLabel(
    reasoning,
    currentModelId,
    currentReasoning,
  );
  const supportedLevels = getSupportedReasoningLevels(reasoning, currentModelId);

  useEffect(() => {
    if (
      isAgentsEndpoint(endpoint) ||
      !conversation ||
      conversation.reasoning_effort != null ||
      !getDefaultReasoningLevel(reasoning, currentModelId)
    ) {
      return;
    }
    setOption('reasoning_effort')(getDefaultReasoningLevel(reasoning, currentModelId));
  }, [conversation, currentModelId, endpoint, reasoning, setOption]);

  if (isAgentsEndpoint(endpoint)) {
    return null;
  }

  const selectModel = (spec: TModelSpec) => {
    handleSelectSpec(spec);
    const nextModelId = spec.preset.model ?? '';
    setOption('reasoning_effort')(
      getNextReasoningLevel(reasoning, nextModelId, currentReasoning),
    );
  };

  const setReasoning = (level: AgentOSReasoningLevel) => {
    setOption('reasoning_effort')(level);
  };

  const trigger = (
    <button
      type="button"
      data-testid="agentos-model-selector-button"
      aria-label={`${currentModelLabel}，推理强度${currentReasoningLabel}`}
      className="my-1 flex h-9 w-full max-w-[70vw] items-center justify-center gap-2 rounded-xl border border-border-light bg-presentation px-3 py-2 text-sm text-text-primary hover:bg-surface-active-alt"
    >
      <Cpu className="size-4 shrink-0 text-text-secondary" aria-hidden="true" />
      <span className="min-w-0 truncate">{currentModelLabel}</span>
      <span className="shrink-0 border-l border-border-light pl-2 text-text-secondary">
        {currentReasoningLabel}
      </span>
    </button>
  );

  return (
    <div className="relative flex w-full max-w-md flex-col items-center gap-2">
      <Menu trigger={trigger}>
        <Menu
          trigger={
            <MenuItem
              data-testid="agentos-model-menu"
              className="flex w-full items-center gap-2 px-3 py-2"
            >
              <Cpu className="size-4 text-text-secondary" aria-hidden="true" />
              <span className="min-w-0 flex-1 text-left">模型</span>
              <span className="max-w-[12rem] truncate text-text-secondary">{currentModelLabel}</span>
              <ChevronRight className="size-4 shrink-0" aria-hidden="true" />
            </MenuItem>
          }
        >
          {modelSpecs.map((spec) => (
            <MenuItem
              key={spec.name}
              data-testid={`agentos-model-option-${spec.preset.model}`}
              aria-selected={selectedValues.modelSpec === spec.name || undefined}
              onClick={() => selectModel(spec)}
              className="flex w-full items-center gap-2 px-3 py-2"
            >
              <ModelRow spec={spec} selected={selectedValues.modelSpec === spec.name} />
            </MenuItem>
          ))}
        </Menu>

        <Menu
          trigger={
            <MenuItem
              data-testid="agentos-reasoning-menu"
              className="flex w-full items-center gap-2 px-3 py-2"
            >
              <BrainCircuit className="size-4 text-text-secondary" aria-hidden="true" />
              <span className="min-w-0 flex-1 text-left">推理强度</span>
              <span className="shrink-0 text-text-secondary">{currentReasoningLabel}</span>
              <ChevronRight className="size-4 shrink-0" aria-hidden="true" />
            </MenuItem>
          }
        >
          {supportedLevels.length > 0 ? (
            supportedLevels.map((level) => (
              <MenuItem
                key={level}
                data-testid={`agentos-reasoning-option-${level}`}
                aria-selected={currentReasoning === level || undefined}
                onClick={() => setReasoning(level)}
                className={cn('flex w-full items-center gap-2 px-3 py-2')}
              >
                <BrainCircuit className="size-4 text-text-secondary" aria-hidden="true" />
                <span className="flex-1 text-left">{AGENTOS_REASONING_LABELS[level]}</span>
                {currentReasoning === level && <Check className="size-4" aria-hidden="true" />}
              </MenuItem>
            ))
          ) : (
            <MenuItem
              aria-disabled="true"
              onClick={(event) => event.preventDefault()}
              className="flex w-full cursor-not-allowed items-center gap-2 px-3 py-2 text-text-secondary"
            >
              <BrainCircuit className="size-4" aria-hidden="true" />
              <span>{localize('com_ui_not_available') || '当前模型未开放推理强度'}</span>
            </MenuItem>
          )}
        </Menu>
      </Menu>
    </div>
  );
}
