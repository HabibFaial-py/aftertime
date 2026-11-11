import { Link, router } from 'expo-router';
import { useRef, useState } from 'react';
import { Text, TextInput, View } from 'react-native';
import { authError, supabase } from '../lib/supabase';
import { Action, Screen, styles } from './ui';

export function AuthForm({ signup = false }: { signup?: boolean }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const submitting = useRef(false);

  async function submit() {
    if (submitting.current || !supabase) return;
    const normalizedEmail = email.trim().toLowerCase();
    if (!normalizedEmail.includes('@') || !password) {
      setError('Enter your email address and password.');
      return;
    }
    submitting.current = true;
    setBusy(true);
    setError('');
    try {
      const credentials = { email: normalizedEmail, password };
      const { data, error: failure } = signup
        ? await supabase.auth.signUp(credentials)
        : await supabase.auth.signInWithPassword(credentials);
      if (failure) { setError(authError(failure)); return; }
      setPassword('');
      if (signup && !data.session) router.replace('/confirm-email');
      // Session events drive protected navigation after sign-in.
    } catch (failure) {
      setError(authError(failure));
    } finally {
      submitting.current = false;
      setBusy(false);
    }
  }

  return <Screen>
    <Text accessibilityRole="header" style={styles.title}>{signup ? 'Create your account' : 'Welcome back'}</Text>
    <Text style={styles.text}>{signup ? 'A little space for words worth waiting for. Confirm your email before signing in.' : 'Sign in to AfterTime.'}</Text>
    <View><Text style={styles.label}>Email</Text>
      <TextInput accessibilityLabel="Email" style={styles.input} value={email} onChangeText={setEmail} keyboardType="email-address" autoCapitalize="none" autoCorrect={false} autoComplete="email" editable={!busy} />
    </View>
    <View><Text style={styles.label}>Password</Text>
      <TextInput accessibilityLabel="Password" style={styles.input} value={password} onChangeText={setPassword} secureTextEntry autoCapitalize="none" autoCorrect={false} autoComplete={signup ? 'new-password' : 'current-password'} editable={!busy} onSubmitEditing={() => void submit()} />
    </View>
    {error ? <Text accessibilityRole="alert" accessibilityLiveRegion="polite" style={styles.error}>{error}</Text> : null}
    <Action title={busy ? 'Please wait…' : signup ? 'Sign up' : 'Sign in'} disabled={busy} onPress={() => void submit()} />
    {!busy && <Link href={signup ? '/sign-in' : '/sign-up'} style={styles.link}>{signup ? 'Already have an account? Sign in' : 'Create an account'}</Link>}
    {!busy && !signup && <Link href="/confirm-email" style={styles.link}>Need a confirmation email?</Link>}
  </Screen>;
}
