import { localInstant } from './capsule-create';

type UnlockTime =
  | { ok: true; utc: string; offset: string }
  | { ok: false; error: string };

// The backend's 90-day limit is elapsed time, not 90 local calendar days.
export function validateDirectUnlockTime(date: string, time: string, now = Date.now()): UnlockTime {
  const local = localInstant(date, time);
  if (!local) {
    return { ok: false, error: 'Enter a valid, unambiguous local date and time. Times during clock changes may not be available.' };
  }
  if (local.getTime() <= now || local.getTime() > now + 90 * 86400000) {
    return { ok: false, error: 'Choose a time in the future within 90 days.' };
  }
  const minutes = -local.getTimezoneOffset();
  const sign = minutes >= 0 ? '+' : '-';
  const hours = String(Math.floor(Math.abs(minutes) / 60)).padStart(2, '0');
  const remainder = String(Math.abs(minutes) % 60).padStart(2, '0');
  return { ok: true, utc: local.toISOString(), offset: `UTC${sign}${hours}:${remainder}` };
}
