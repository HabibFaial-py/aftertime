import { useRef, useState } from 'react';
import { Text } from 'react-native';
import { useAuth } from '../lib/auth';
import { authError, supabase } from '../lib/supabase';
import { Action, Screen, styles } from '../components/ui';

export default function Home() {
  const { session } = useAuth();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const submitting = useRef(false);
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
    {error ? <Text accessibilityRole="alert" style={styles.error}>{error}</Text> : null}
    <Action title={busy ? 'Signing out…' : 'Log out'} disabled={busy} onPress={() => void logout()} />
  </Screen>;
}
