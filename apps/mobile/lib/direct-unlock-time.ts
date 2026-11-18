import { localInstant } from './capsule-create';

type UnlockTime =
  | { ok: true; utc: string; offset: string }
  | { ok: false; error: string };

export type DirectTimeReview = {
  date: string; time: string; timezone: string; offset: string; utc: string;
  wallClock: number; monotonicClock: number;
};

// A small tolerance accounts for the two clock readings and timer scheduling.
// Any future submission must also revalidate synchronously against the review.
export function isDirectTimeReviewCurrent(review: DirectTimeReview, now: number, monotonic: number, timezone: string): boolean {
  const instant = new Date(review.utc);
  const pad = (value: number) => String(value).padStart(2, '0');
  const localDate = `${instant.getFullYear()}-${pad(instant.getMonth() + 1)}-${pad(instant.getDate())}`;
  const localTime = `${pad(instant.getHours())}:${pad(instant.getMinutes())}`;
  const elapsed = monotonic - review.monotonicClock;
  return timezone === review.timezone && Number.isFinite(instant.getTime()) &&
    localDate === review.date && localTime === review.time &&
    instant.getTime() > now && instant.getTime() <= now + 90 * 86400000 &&
    elapsed >= 0 && Math.abs((now - review.wallClock) - elapsed) <= 1000;
}

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
