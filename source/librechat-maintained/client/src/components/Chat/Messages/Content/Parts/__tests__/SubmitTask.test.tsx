import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import type { SubmitSnapshot } from 'librechat-data-provider';
import { ChatContext } from '~/Providers/ChatContext';
import SubmitTask, { submitTaskId } from '../SubmitTask';

let mockData: SubmitSnapshot | undefined;
let mockError = false;
const mockDownload = jest.fn();
const mockTrigger = jest.fn();
const mockRefetch = jest.fn();
jest.mock('~/Providers/ChatContext', () => ({ ChatContext: require('react').createContext(null) }));
jest.mock('~/hooks', () => ({ useLocalize: () => (key: string) => key }));
jest.mock('~/utils', () => ({ triggerDownload: (...args: Parameters<typeof mockTrigger>) => mockTrigger(...args) }));
jest.mock('~/data-provider', () => ({
  useSubmitTask: () => ({ data: mockData, isError: mockError, isFetching: false, refetch: mockRefetch }),
  useSubmitDownload: () => ({ mutateAsync: mockDownload, isLoading: false }),
}));

const context = { conversation: { agent_id: 'agent_smart_submit_v1', conversationId: 'conversation-a' } } as
  NonNullable<React.ContextType<typeof ChatContext>>;
const renderTask = () => render(<ChatContext.Provider value={context}>
  <SubmitTask output='{"task_id":"task-a"}' />
</ChatContext.Provider>);

describe('Submit task report view', () => {
  beforeEach(() => { mockData = undefined; mockError = false; jest.clearAllMocks(); });
  test('does not accept invented task identifiers or malformed tool output', () => {
    expect(submitTaskId('not-json')).toBe('');
    expect(submitTaskId('{"task_id":"../../private"}')).toBe('');
    expect(submitTaskId('{"status":"pricing_required"}')).toBe('');
  });
  test('shows loading without claiming success', () => {
    renderTask();
    expect(screen.getByRole('status')).toHaveTextContent('com_ui_loading');
  });
  test('shows access failure and permits a retry', () => {
    mockError = true;
    renderTask();
    expect(screen.getByRole('status')).toHaveTextContent('com_ui_submit_unavailable');
    fireEvent.click(screen.getByRole('button', { name: 'com_ui_retry' }));
    expect(mockRefetch).toHaveBeenCalledTimes(1);
  });
  test('downloads an artifact only through the authenticated data service', async () => {
    mockData = { task: { task_id: 'task-a', site_key: 'xinan_high_school', month: '2026-05',
      status: 'completed', missing_roles: [] }, artifacts: [{ artifact_id: 'art_abcdefghijklmnopqr',
      file_name: 'report.xlsx', size: 20, sha256: '0'.repeat(64), kind: 'output', role: 'output', status: 'available' }] };
    const blob = new Blob(['report']);
    mockDownload.mockResolvedValue({ data: blob });
    renderTask();
    fireEvent.click(screen.getByRole('button', { name: 'com_ui_download report.xlsx' }));
    await waitFor(() => expect(mockTrigger).toHaveBeenCalledWith(expect.any(String), 'report.xlsx'));
    expect(mockDownload).toHaveBeenCalledWith('art_abcdefghijklmnopqr');
  });
  test('does not expose live task access outside an authenticated chat context', () => {
    render(<SubmitTask output='{"task_id":"task-a"}' />);
    expect(screen.queryByRole('region')).not.toBeInTheDocument();
  });
});
