import { Link } from 'expo-router';
import { useRef, useState } from 'react';
import { Text, TextInput } from 'react-native';
import { Action, Screen, styles } from '../components/ui';
import { authError, supabase } from '../lib/supabase';

export default function ConfirmEmail() {
  const [email, setEmail] = useState('');
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const submitting = useRef(false);
  async function resend() {
    if (!supabase || submitting.current) return;
    if (!email.trim().includes('@')) { setMessage('Enter your email address.'); return; }
    submitting.current = true;
    setBusy(true);
    try {
      const { error } = await supabase.auth.resend({ type: 'signup', email: email.trim().toLowerCase() });
      setMessage(error ? authError(error) : 'If confirmation is needed, a new email is on its way.');
    } catch (error) { setMessage(authError(error)); }
    finally { submitting.current = false; setBusy(false); }
  }
  return <Screen>
    <Text accessibilityRole="header" style={styles.title}>Check your email</Text>
    <Text style={styles.text}>If your account needs confirmation, open the link in your email using your browser. Then return to AfterTime and sign in.</Text>
    <Text style={styles.text}>Check your spam folder too. If you already have an account, try signing in. If the link has expired, request another confirmation below.</Text>
    <TextInput accessibilityLabel="Email for confirmation" style={styles.input} value={email} onChangeText={setEmail} keyboardType="email-address" autoComplete="email" autoCorrect={false} autoCapitalize="none" editable={!busy} placeholder="Email address" placeholderTextColor="#6A5C52" />
    <Action title={busy ? 'Sending…' : 'Resend confirmation'} disabled={busy} onPress={() => void resend()} />
    {message ? <Text accessibilityLiveRegion="polite" style={styles.text}>{message}</Text> : null}
    <Link href="/sign-in" style={styles.link}>Return to sign in</Link>
  </Screen>;
}
