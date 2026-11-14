import { ApiError } from './api';
import { CapsuleListItem, listCapsules } from './capsules';

const PAGE_SIZE = 50;
type Phase = 'loading' | 'refreshing' | 'loadingMore' | 'ready' | 'error';
export type ListState = { items: CapsuleListItem[]; phase: Phase; error: string; hasMore: boolean };
type FetchPage = typeof listCapsules;

export class CapsuleListController {
  private state: ListState = { items: [], phase: 'loading', error: '', hasMore: false };
  private request: AbortController | null = null;
  private generation = 0;
  private offset = 0;
  private disposed = false;

  constructor(private readonly userId: string, private readonly onChange: (state: ListState) => void, private readonly fetchPage: FetchPage = listCapsules) {}

  dispose() {
    this.disposed = true;
    this.generation++;
    this.request?.abort();
    this.state = { items: [], phase: 'loading', error: '', hasMore: false };
  }

  refresh(initial = false) { return this.load(true, initial); }
  loadMore() {
    if (!this.state.hasMore || this.request) return Promise.resolve();
    return this.load(false, false);
  }

  private async load(reset: boolean, initial: boolean) {
    if (this.disposed) return;
    this.request?.abort();
    const controller = new AbortController();
    this.request = controller;
    const generation = ++this.generation;
    const offset = reset ? 0 : this.offset;
    this.update({ ...this.state, phase: initial ? 'loading' : reset ? 'refreshing' : 'loadingMore', error: '' });
    try {
      const page = await this.fetchPage(this.userId, controller.signal, PAGE_SIZE, offset);
      if (this.disposed || generation !== this.generation || controller.signal.aborted) return;
      const items = reset ? [] : [...this.state.items];
      const seen = new Set(items.map((item) => item.id.toLowerCase()));
      for (const item of page) {
        if (!seen.has(item.id.toLowerCase())) {
          seen.add(item.id.toLowerCase());
          // Explicit projection prevents additional properties reaching the view.
          items.push({ id: item.id, title: item.title, status: item.status, unlock_at: item.unlock_at, created_at: item.created_at });
        }
      }
      this.offset = offset + page.length;
      this.update({ items, phase: 'ready', error: '', hasMore: page.length === PAGE_SIZE && this.offset <= 10000 });
    } catch (error) {
      if (this.disposed || generation !== this.generation || controller.signal.aborted) return;
      const authFailure = error instanceof ApiError && (error.kind === 'session' || error.kind === 'unauthorized');
      this.update({ ...this.state, items: authFailure ? [] : this.state.items, phase: 'error', error: authFailure
        ? 'Your session could not be verified. Sign in again or retry.'
        : 'Could not load your capsules. Check your connection and retry.' });
    } finally {
      if (generation === this.generation) this.request = null;
    }
  }

  private update(state: ListState) {
    this.state = state;
    this.onChange(state);
  }
}
