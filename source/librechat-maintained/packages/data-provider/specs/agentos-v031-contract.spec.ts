import createPayload from '../src/createPayload';

describe('AgentOS V0.3.1 request contract', () => {
  it('passes the selected internal model and reasoning effort to the native payload', () => {
    const { payload } = createPayload({
      userMessage: { text: 'contract test' },
      conversation: {
        conversationId: '00000000-0000-0000-0000-000000000001',
        endpoint: 'custom',
      },
      endpointOption: {
        endpoint: 'custom',
        model: 'gpt-5.6-sol',
        reasoning_effort: 'high',
      },
      isTemporary: true,
    } as any);

    expect(payload.endpoint).toBe('custom');
    expect(payload.model).toBe('gpt-5.6-sol');
    expect(payload.reasoning_effort).toBe('high');
    expect(payload).not.toHaveProperty('modelLabel', 'GPT-5.6 Sol Agent');
  });

  it('keeps an unset reasoning value unset for an explicitly automatic request', () => {
    const { payload } = createPayload({
      userMessage: { text: 'contract test' },
      conversation: {
        conversationId: '00000000-0000-0000-0000-000000000002',
        endpoint: 'custom',
      },
      endpointOption: {
        endpoint: 'custom',
        model: 'gpt-5.5',
        reasoning_effort: '',
      },
      isTemporary: true,
    } as any);

    expect(payload.model).toBe('gpt-5.5');
    expect(payload.reasoning_effort).toBe('');
  });
});
