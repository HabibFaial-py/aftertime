import { useEffect, useRef, useState } from 'react';
import { Text, TextInput } from 'react-native';
import { router } from 'expo-router';
import { Action, Screen, styles } from '../components/ui';
import { useAuth } from '../lib/auth';
import { CapsuleSubmission, validateDraft } from '../lib/capsule-create';

const sessionKeys = new WeakMap<object, number>();
let nextKey = 0;
function sessionKey(session: object) {
  let key = sessionKeys.get(session);
  if (key === undefined) { key = ++nextKey; sessionKeys.set(session, key); }
  return key;
}

function CreateForm({ userId }: { userId: string }) {
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [date, setDate] = useState('');
  const [time, setTime] = useState('');
  const [confirming, setConfirming] = useState(false);
  const [reviewed, setReviewed] = useState<{ instant: string; timezone: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [uncertain, setUncertain] = useState(false);
  const [error, setError] = useState('');
  const submitter = useRef<CapsuleSubmission | null>(null);
  const pending = useRef(false);
  useEffect(() => {
    const current = new CapsuleSubmission(userId);
    submitter.current = current;
    return () => { current.dispose(); submitter.current = null; };
  }, [userId]);

  const draft = { title, body, date, time };
  const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone || 'device local time';
  function review() {
    const result = validateDraft(draft);
    if (!result.ok) { setError(result.error); return; }
    setReviewed({ instant: result.request.unlock_at, timezone });
    setError(''); setConfirming(true);
  }
  async function seal() {
    if (pending.current || !submitter.current || uncertain) return;
    const result = validateDraft(draft);
    if (!result.ok) { setError(result.error); setConfirming(false); return; }
    if (!reviewed || reviewed.instant !== result.request.unlock_at || reviewed.timezone !== timezone) {
      setError('Your device time or timezone changed. Review the reveal time again.'); setConfirming(false); return;
    }
    pending.current = true; setBusy(true); setError('');
    const outcome = await submitter.current.submit(result.request);
    if (outcome === 'cancelled' || outcome === null) return;
    pending.current = false; setBusy(false);
    if (outcome === 'success') { setBody(''); router.replace('/capsules'); return; }
    if (outcome === 'uncertain') {
      setUncertain(true);
      setError('Your capsule may have been created. Refresh your capsule list before attempting to create it again.');
    } else if (outcome === 'auth') setError('Your session could not be verified. Sign in again or retry.');
    else if (outcome === 'invalid') { setConfirming(false); setError('The server could not accept this capsule. Check your text and reveal time.'); }
    else setError('The service is unavailable. Check your configuration and retry.');
  }
  const current = confirming ? validateDraft(draft) : null;
  return <Screen>
    <Text accessibilityRole="header" style={styles.title}>Create a capsule</Text>
    {!confirming ? <>
      <Text style={styles.label}>Title</Text>
      <TextInput accessibilityLabel="Title" style={styles.input} value={title} onChangeText={setTitle} editable={!busy} />
      <Text style={styles.label}>Private message</Text>
      <TextInput accessibilityLabel="Private message" style={styles.input} value={body} onChangeText={setBody} multiline editable={!busy} autoCorrect={false} autoComplete="off" />
      <Text style={styles.text}>{Array.from(body).length} / 2,000 characters</Text>
      <Text style={styles.label}>Local reveal date (YYYY-MM-DD)</Text>
      <TextInput accessibilityLabel="Local reveal date, year month day" style={styles.input} value={date} onChangeText={setDate} placeholder="YYYY-MM-DD" placeholderTextColor="#6A5C52" editable={!busy} />
      <Text style={styles.label}>Local reveal time, 24-hour (HH:MM)</Text>
      <TextInput accessibilityLabel="Local reveal time, 24-hour hours and minutes" style={styles.input} value={time} onChangeText={setTime} placeholder="HH:MM" placeholderTextColor="#6A5C52" editable={!busy} />
      <Text style={styles.text}>Timezone: {timezone}. Enter the local date and time on your device.</Text>
      <Action title="Review capsule" onPress={review} />
    </> : <>
      <Text style={styles.label}>Title: {title}</Text>
      <Text style={styles.text}>Reveal: {current?.ok ? current.local.toLocaleString() : `${date} ${time}`}</Text>
      <Text style={styles.text}>Timezone: {timezone}{current?.ok ? ` (UTC${-current.local.getTimezoneOffset() >= 0 ? '+' : '-'}${String(Math.floor(Math.abs(current.local.getTimezoneOffset()) / 60)).padStart(2, '0')}:${String(Math.abs(current.local.getTimezoneOffset()) % 60).padStart(2, '0')})` : ''}</Text>
      <Text style={styles.text}>This capsule cannot be revealed before the server-authorized time.</Text>
      {!uncertain && <><Action title={busy ? 'Sealing…' : 'Seal capsule'} disabled={busy} onPress={() => void seal()} />
        <Action title="Edit" disabled={busy} onPress={() => { setConfirming(false); setError(''); }} /></>}
    </>}
    {error ? <Text accessibilityRole="alert" style={styles.error}>{error}</Text> : null}
    <Action title={uncertain ? 'Return to capsule list' : 'Back to capsules'} disabled={busy} onPress={() => router.replace('/capsules')} />
  </Screen>;
}

export default function CreateCapsuleScreen() {
  const { session } = useAuth();
  return session ? <CreateForm key={sessionKey(session)} userId={session.user.id} /> : null;
}
