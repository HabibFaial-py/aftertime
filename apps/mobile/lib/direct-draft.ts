import { validateDirectUnlockTime } from './direct-unlock-time';

type DirectDraft = { recipient: string; title: string; body: string; date: string; time: string };

// Unpaired UTF-16 surrogates cannot be encoded as valid UTF-8 by the API.
function hasInvalidUnicode(value: string): boolean {
  return Array.from(value).some((character) => {
    const code = character.codePointAt(0)!;
    return code >= 0xD800 && code <= 0xDFFF;
  });
}

// This validates only. There is no direct-capsule submission in this slice.
export function validateDirectDraft(draft: DirectDraft, now = Date.now()) {
  const recipient = draft.recipient.trim().toLowerCase();
  if (Array.from(draft.recipient).length > 254 || Array.from(recipient).length > 254 ||
      !/^[^@\s]+@[^@\s]+$/.test(recipient) || recipient.includes('\0') || hasInvalidUnicode(recipient)) {
    return { ok: false as const, field: 'recipient' as const, error: 'Enter a valid recipient email address.' };
  }
  if (!draft.title.trim()) return { ok: false as const, field: 'title' as const, error: 'Enter a title.' };
  if (!draft.body.trim()) return { ok: false as const, field: 'body' as const, error: 'Enter a message.' };
  if (draft.title.includes('\0') || hasInvalidUnicode(draft.title)) {
    return { ok: false as const, field: 'title' as const, error: 'Remove invalid characters from your title.' };
  }
  if (draft.body.includes('\0') || hasInvalidUnicode(draft.body)) {
    return { ok: false as const, field: 'body' as const, error: 'Remove invalid characters from your message.' };
  }
  if (Array.from(draft.body).length > 2000) {
    return { ok: false as const, field: 'body' as const, error: 'Your message must be 2,000 characters or fewer.' };
  }
  const time = validateDirectUnlockTime(draft.date, draft.time, now);
  return time.ok ? time : { ...time, field: 'dateTime' as const };
}
