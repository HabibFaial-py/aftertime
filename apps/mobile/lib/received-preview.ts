import type { ReceivedSource, RecipientInboxItem } from './received-capsules';

export const receivedPreviewScenarios = [
  { id: 'inbox', label: 'Locked and unlocked' },
  { id: 'empty', label: 'Empty inbox' },
  { id: 'unavailable', label: 'Inbox unavailable' },
  { id: 'loadError', label: 'Inbox error then retry' },
  { id: 'revealDenied', label: 'Reveal unavailable' },
  { id: 'revealUncertain', label: 'Reveal uncertain' },
  { id: 'authInterrupted', label: 'Sign-in interrupted' },
] as const;

export type ReceivedPreviewScenario = typeof receivedPreviewScenarios[number]['id'];

function pause(signal: AbortSignal): Promise<void> {
  return new Promise((resolve) => {
    if (signal.aborted) { resolve(); return; }
    const timer = setTimeout(finish, 300);
    signal.addEventListener('abort', finish, { once: true });
    function finish() {
      clearTimeout(timer);
      signal.removeEventListener('abort', finish);
      resolve();
    }
  });
}

export function createReceivedPreview(scenario: ReceivedPreviewScenario): ReceivedSource {
  const now = Date.now();
  const day = 86_400_000;
  const locked: RecipientInboxItem = {
    id: '00000000-0000-4000-8000-000000000251',
    sender_id: '00000000-0000-4000-8000-000000000253',
    created_at: new Date(now - day).toISOString(),
    unlock_at: new Date(now + day).toISOString(),
    status: 'locked',
  };
  const unlocked: RecipientInboxItem = {
    id: '00000000-0000-4000-8000-000000000252',
    sender_id: '00000000-0000-4000-8000-000000000254',
    created_at: new Date(now - 4 * day).toISOString(),
    unlock_at: new Date(now - day).toISOString(),
    status: 'unlocked',
  };
  let failedLoad = false;
  let withdrawn = false;

  return {
    async load(signal) {
      await pause(signal);
      if (signal.aborted || scenario === 'unavailable') return { status: 'unavailable' };
      if (scenario === 'loadError' && !failedLoad) {
        failedLoad = true;
        return { status: 'error' };
      }
      return { status: 'ok', items: scenario === 'empty' ? [] : withdrawn ? [locked] : [locked, unlocked] };
    },
    async reveal(id, signal) {
      await pause(signal);
      if (signal.aborted || id !== unlocked.id || scenario === 'empty' || scenario === 'unavailable') return { status: 'unavailable' };
      if (scenario === 'revealDenied') {
        // Cancelled, deleted and revoked bindings share the same unavailable response.
        withdrawn = true;
        return { status: 'unavailable' };
      }
      if (scenario === 'revealUncertain') return { status: 'uncertain' };
      if (scenario === 'authInterrupted') return { status: 'auth' };
      return { status: 'ok', message: { id, body: 'I hope you saved an afternoon for yourself this week.' } };
    },
  };
}
