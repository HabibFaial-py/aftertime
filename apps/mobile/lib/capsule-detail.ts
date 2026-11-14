import { ApiError } from './api';
import { CapsuleListItem, cancelCapsule, listCapsules, revealCapsule } from './capsules';

export const validCapsuleId = (id: unknown): id is string => typeof id === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id);
export type DetailState = {
  metadata: CapsuleListItem | null;
  phase: 'loading' | 'ready' | 'unavailable' | 'error' | 'revealing' | 'revealed' | 'confirmCancel' | 'cancelling' | 'cancelled' | 'cancelUncertain';
  error: string;
  body: string | null;
};
export const emptyDetail = (): DetailState => ({ metadata: null, phase: 'loading', error: '', body: null });

function safeError(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.status === 404) return 'This capsule is unavailable.';
    if (error.kind === 'session' || error.kind === 'unauthorized') return 'Your session could not be verified. Sign in again or retry.';
    if (error.status === 503) return 'The service is unavailable. Please try again.';
    if (error.kind === 'timeout') return 'The request timed out. Please try again.';
    if (error.kind === 'network') return 'Could not connect. Check your connection and retry.';
    if (error.kind === 'cancelled') return 'The request was cancelled.';
  }
  return 'Could not complete the request. Please try again.';
}

export class CapsuleDetailController {
  private state = emptyDetail();
  private request: AbortController | null = null;
  private generation = 0;
  private disposed = false;
  constructor(private readonly userId: string, private readonly id: string,
    private readonly onChange: (state: DetailState) => void,
    private readonly list: typeof listCapsules = listCapsules,
    private readonly revealMessage: typeof revealCapsule = revealCapsule,
    private readonly cancelMessage: typeof cancelCapsule = cancelCapsule) {}

  dispose() {
    this.disposed = true;
    this.generation++;
    this.request?.abort();
    this.state = emptyDetail();
  }

  async load() {
    if (this.disposed) return;
    this.request?.abort();
    const controller = new AbortController();
    this.request = controller;
    const generation = ++this.generation;
    this.update(emptyDetail());
    if (!validCapsuleId(this.id)) {
      this.request = null;
      this.update({ ...emptyDetail(), phase: 'unavailable' });
      return;
    }
    try {
      for (let offset = 0; offset <= 10000; offset += 50) {
        const page = await this.list(this.userId, controller.signal, 50, offset);
        if (!this.current(generation, controller)) return;
        const item = page.find((entry) => entry.id.toLowerCase() === this.id.toLowerCase());
        if (item) {
          this.update({ metadata: { id: item.id, title: item.title, unlock_at: item.unlock_at, created_at: item.created_at, status: item.status }, phase: 'ready', body: null, error: '' });
          return;
        }
        if (page.length < 50) break;
      }
      if (this.current(generation, controller)) this.update({ ...emptyDetail(), phase: 'unavailable' });
    } catch (error) {
      if (this.current(generation, controller)) this.update({ ...emptyDetail(), phase: 'error', error: safeError(error) });
    } finally { if (generation === this.generation) this.request = null; }
  }

  async reveal() {
    if (this.disposed || this.request || !this.state.metadata || (this.state.phase !== 'ready' && this.state.phase !== 'error')) return;
    const controller = new AbortController();
    this.request = controller;
    const generation = ++this.generation;
    this.update({ ...this.state, phase: 'revealing', error: '', body: null });
    try {
      const result = await this.revealMessage(this.userId, controller.signal, this.id);
      if (this.current(generation, controller)) this.update({ ...this.state, phase: 'revealed', body: result.body, error: '' });
    } catch (error) {
      if (this.current(generation, controller)) this.update({ ...this.state, phase: 'error', body: null, error: safeError(error) });
    } finally { if (generation === this.generation) this.request = null; }
  }

  requestCancellation() {
    if (this.disposed || this.request || !this.state.metadata || !['ready', 'revealed', 'error'].includes(this.state.phase)) return;
    this.update({ ...this.state, phase: 'confirmCancel', error: '' });
  }

  keepCapsule() {
    if (this.disposed || this.state.phase !== 'confirmCancel') return;
    this.update({ ...this.state, phase: this.state.body !== null ? 'revealed' : 'ready', error: '' });
  }

  async confirmCancellation(): Promise<boolean> {
    if (this.disposed || this.request || !this.state.metadata || this.state.phase !== 'confirmCancel') return false;
    const controller = new AbortController();
    this.request = controller;
    const generation = ++this.generation;
    this.update({ ...this.state, phase: 'cancelling', error: '' });
    try {
      await this.cancelMessage(this.userId, controller.signal, this.id);
      if (!this.current(generation, controller)) return false;
      this.update({ metadata: null, phase: 'cancelled', error: '', body: null });
      return true;
    } catch (error) {
      if (!this.current(generation, controller)) return false;
      if (error instanceof ApiError && (error.kind === 'session' || error.kind === 'unauthorized' || error.status === 404 || error.kind === 'config')) {
        this.update({ ...this.state, phase: 'error', body: null, error: safeError(error) });
      } else {
        // A request may commit before a timeout, 503, cancellation or malformed response.
        this.update({ metadata: null, phase: 'cancelUncertain', body: null, error: 'The service could not confirm cancellation. Cancellation may have succeeded. Refresh your capsule list before trying again.' });
      }
      return false;
    } finally { if (generation === this.generation) this.request = null; }
  }

  private current(generation: number, controller: AbortController) {
    return !this.disposed && generation === this.generation && !controller.signal.aborted;
  }
  private update(state: DetailState) { this.state = state; this.onChange(state); }
}
