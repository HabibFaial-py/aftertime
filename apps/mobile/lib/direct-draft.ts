import { validateDraft } from './capsule-create';

type DirectDraft = { recipient: string; title: string; body: string; date: string; time: string };

// Unpaired UTF-16 surrogates cannot be encoded as valid UTF-8 by the API.
function hasInvalidUnicode(value: string): boolean {
  return Array.from(value).some((character) => {
    const code = character.codePointAt(0)!;
    return code >= 0xD800 && code <= 0xDFFF;
  });
}

// This validates only. There is no direct-capsule submission in this slice.
export function validateDirectDraft(draft: DirectDraft, now = Date.now()): string {
  const recipient = draft.recipient.trim().toLowerCase();
  if (Array.from(draft.recipient).length > 254 || Array.from(recipient).length > 254 ||
      !/^[^@\s]+@[^@\s]+$/.test(recipient) || recipient.includes('\0') || hasInvalidUnicode(recipient)) {
    return 'Enter a valid recipient email address.';
  }
  if (!draft.title.trim()) return 'Enter a title.';
  if (!draft.body.trim()) return 'Enter a message.';
  if (hasInvalidUnicode(draft.title) || hasInvalidUnicode(draft.body)) {
    return 'Remove invalid characters from your text.';
  }
  // Reuse the self-capsule text and local time rules without creating a request.
  const result = validateDraft({ title: draft.title, body: draft.body, date: draft.date, time: draft.time }, now);
  return result.ok ? '' : result.error;
}
