// Recipient inbox metadata mirrors the backend projection. IDs are UUID strings.
export type RecipientInboxItem = Readonly<{
  id: string;
  sender_id: string;
  created_at: string;
  unlock_at: string;
  status: 'locked' | 'unlocked';
}>;

type RecipientMessage = Readonly<{ id: string; body: string }>;
type InboxOutcome = { status: 'ok'; items: readonly RecipientInboxItem[] } | { status: 'unavailable' | 'error' | 'auth' };
type RevealOutcome = { status: 'ok'; message: RecipientMessage } | { status: 'unavailable' | 'uncertain' | 'auth' };

export type ReceivedSource = {
  load(signal: AbortSignal): Promise<InboxOutcome>;
  reveal(id: string, signal: AbortSignal): Promise<RevealOutcome>;
};

type RevealState = { phase: 'idle' } | { phase: 'revealing' | 'unavailable' | 'uncertain'; id: string }
  | { phase: 'revealed'; id: string; body: string };
export type ReceivedState = { phase: 'loading' | 'empty' | 'unavailable' | 'error' | 'auth' }
  | { phase: 'ready'; items: readonly RecipientInboxItem[]; reveal: RevealState };

export function canReveal(item: RecipientInboxItem, reveal: RevealState) {
  return item.status === 'unlocked' && reveal.phase !== 'revealing'
    && (reveal.phase === 'idle' || reveal.id !== item.id);
}

export class ReceivedCapsulesController {
  private state: ReceivedState = { phase: 'loading' };
  private request: AbortController | null = null;
  private disposed = false;

  constructor(private readonly source: ReceivedSource, private readonly onChange: (state: ReceivedState) => void) {}

  dispose() {
    this.disposed = true;
    this.request?.abort();
    this.request = null;
    this.state = { phase: 'loading' };
  }

  async refresh() {
    if (this.disposed || this.state.phase === 'auth') return;
    this.request?.abort();
    const request = new AbortController();
    this.request = request;
    this.update({ phase: 'loading' });
    try {
      const response = await this.source.load(request.signal);
      if (this.request !== request) return;
      if (response.status !== 'ok') {
        this.update({ phase: response.status });
        return;
      }
      // Keep the list metadata-only even if a source sends extra properties.
      const items = response.items.map(({ id, sender_id, created_at, unlock_at, status }) =>
        ({ id, sender_id, created_at, unlock_at, status }));
      this.update(items.length ? { phase: 'ready', items, reveal: { phase: 'idle' } } : { phase: 'empty' });
    } catch {
      if (this.request === request) this.update({ phase: 'error' });
    } finally {
      if (this.request === request) this.request = null;
    }
  }

  async reveal(id: string) {
    if (this.disposed || this.request || this.state.phase !== 'ready') return;
    const { items, reveal } = this.state;
    const item = items.find((entry) => entry.id === id);
    if (!item || !canReveal(item, reveal)) return;

    const request = new AbortController();
    this.request = request;
    this.update({ phase: 'ready', items, reveal: { phase: 'revealing', id } });
    try {
      const response = await this.source.reveal(id, request.signal);
      if (this.request !== request) return;
      if (response.status === 'auth') {
        this.update({ phase: 'auth' });
      } else if (response.status === 'ok' && response.message.id === id && typeof response.message.body === 'string') {
        this.update({ phase: 'ready', items, reveal: { phase: 'revealed', id, body: response.message.body } });
      } else {
        const phase = response.status === 'unavailable' ? 'unavailable' : 'uncertain';
        this.update({ phase: 'ready', items, reveal: { phase, id } });
      }
    } catch {
      if (this.request === request) this.update({ phase: 'ready', items, reveal: { phase: 'uncertain', id } });
    } finally {
      if (this.request === request) this.request = null;
    }
  }

  private update(state: ReceivedState) {
    this.state = state;
    this.onChange(state);
  }
}
