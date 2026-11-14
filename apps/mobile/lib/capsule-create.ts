import { ApiError } from './api';
import { CreateCapsuleRequest, createCapsule } from './capsules';

type Draft = { title: string; body: string; date: string; time: string };
type Validation = { ok: true; request: CreateCapsuleRequest; local: Date } | { ok: false; error: string };

// Detect every matching local minute within 26 hours of the runtime's choice.
// This rejects clock gaps and folds, including non-hour DST transitions.
export function localInstant(date: string, time: string): Date | null {
  const d = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date);
  const t = /^(\d{2}):(\d{2})$/.exec(time);
  if (!d || !t) return null;
  const [year, month, day, hour, minute] = [Number(d[1]), Number(d[2]), Number(d[3]), Number(t[1]), Number(t[2])];
  if (year < 100 || month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59) return null;
  const candidate = new Date(year, month - 1, day, hour, minute, 0, 0);
  const matches = (v: Date) => v.getFullYear() === year && v.getMonth() === month - 1 && v.getDate() === day && v.getHours() === hour && v.getMinutes() === minute && v.getSeconds() === 0;
  if (!matches(candidate)) return null;
  for (let delta = -26 * 60; delta <= 26 * 60; delta++) {
    if (delta !== 0 && matches(new Date(candidate.getTime() + delta * 60000))) return null;
  }
  return candidate;
}

export function validateDraft(draft: Draft, now = Date.now()): Validation {
  if (!draft.title.trim() || !draft.body.trim()) return { ok: false, error: 'Enter a title and message.' };
  if (draft.title.includes('\0') || draft.body.includes('\0')) return { ok: false, error: 'Remove invalid characters from your text.' };
  if (Array.from(draft.body).length > 2000) return { ok: false, error: 'Your message must be 2,000 characters or fewer.' };
  const local = localInstant(draft.date, draft.time);
  if (!local) return { ok: false, error: 'Enter a valid, unambiguous local date and time. Times during clock changes may not be available.' };
  if (local.getTime() <= now || local.getTime() > now + 90 * 86400000) return { ok: false, error: 'Choose a time in the future within 90 days.' };
  return { ok: true, local, request: { title: draft.title, body: draft.body, unlock_at: local.toISOString() } };
}

export type SubmissionResult = 'success' | 'invalid' | 'auth' | 'uncertain' | 'unavailable' | 'cancelled';

export class CapsuleSubmission {
  private controller: AbortController | null = null;
  private disposed = false;
  private uncertain = false;
  constructor(private readonly userId: string, private readonly send: typeof createCapsule = createCapsule) {}

  dispose() { this.disposed = true; this.controller?.abort(); }

  async submit(request: CreateCapsuleRequest): Promise<SubmissionResult | null> {
    if (this.disposed || this.controller || this.uncertain) return null;
    const controller = new AbortController();
    this.controller = controller;
    try {
      await this.send(this.userId, controller.signal, request);
      return this.disposed || controller.signal.aborted ? 'cancelled' : 'success';
    } catch (error) {
      if (this.disposed || controller.signal.aborted) return 'cancelled';
      if (error instanceof ApiError) {
        if (error.kind === 'session' || error.kind === 'unauthorized') return 'auth';
        if (error.status === 422) return 'invalid';
        if (error.kind === 'config') return 'unavailable';
      }
      // A failure after dispatch, including a 503 or malformed 201, can follow a commit.
      this.uncertain = true;
      return 'uncertain';
    } finally { this.controller = null; }
  }
}
