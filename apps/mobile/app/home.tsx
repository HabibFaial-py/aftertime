import { useEffect, useRef, useState } from 'react';
import { Text } from 'react-native';
import { useAuth } from '../lib/auth';
import { authError, supabase } from '../lib/supabase';
import { Action, Screen, styles } from '../components/ui';
import { ApiError, getAuthenticatedUser } from '../lib/api';
import { router } from 'expo-router';

export default function Home() {
  const { session } = useAuth();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const submitting = useRef(false);
  const [backend, setBackend] = useState<'checking' | 'connected' | 'failed'>('checking');
  const [backendMessage, setBackendMessage] = useState('');
  const [retryCount, setRetryCount] = useState(0);
  const userId = session?.user.id;
  const accessToken = session?.access_token;
  useEffect(() => {
    if (!userId || !accessToken) return;
    const controller = new AbortController();
    Promise.resolve().then(() => {
      if (!controller.signal.aborted) setBackend('checking');
      return getAuthenticatedUser(userId, controller.signal);
    }).then(() => {
      if (!controller.signal.aborted) { setBackend('connected'); setBackendMessage(''); }
    }).catch((failure: unknown) => {
      if (controller.signal.aborted) return;
      const kind = failure instanceof ApiError ? failure.kind : 'network';
      const message = kind === 'config' ? 'Set a valid API URL in your mobile environment.'
        : kind === 'session' || kind === 'unauthorized' ? 'Your session could not be verified. Sign in again or retry.'
          : 'The backend is unavailable. Check your connection and retry.';
      setBackendMessage(message);
      setBackend('failed');
    });
    return () => controller.abort();
  }, [userId, accessToken, retryCount]);
  async function logout() {
    if (!supabase || submitting.current) return;
    submitting.current = true;
    setBusy(true);
    setError('');
    try {
      const { error: failure } = await supabase.auth.signOut({ scope: 'local' });
      if (failure) setError(authError(failure));
    } catch (failure) { setError(authError(failure)); }
    finally { submitting.current = false; setBusy(false); }
  }
  return <Screen>
    <Text accessibilityRole="header" style={styles.title}>Welcome to AfterTime</Text>
    <Text style={styles.text}>Write today. Reveal tomorrow.</Text>
    <Text style={styles.text}>Signed in as {session?.user.email}</Text>
    <Text accessibilityLiveRegion="polite" style={styles.text}>Backend authentication: {backend === 'checking' ? 'Checking...' : backend === 'connected' ? 'Connected' : 'Failed'}</Text>
    {backend === 'failed' && <><Text style={styles.error}>{backendMessage}</Text><Action title="Retry connection" onPress={() => { setBackend('checking'); setRetryCount((n) => n + 1); }} /></>}
    {error ? <Text accessibilityRole="alert" style={styles.error}>{error}</Text> : null}
    <Action title="View capsules" onPress={() => router.push('/capsules')} />
    <Action title={busy ? 'Signing out…' : 'Log out'} disabled={busy} onPress={() => void logout()} />
  </Screen>;
}
