import 'react-native-url-polyfill/auto';
import { createClient, processLock } from '@supabase/supabase-js';
import * as SecureStore from 'expo-secure-store';

const url = process.env.EXPO_PUBLIC_SUPABASE_URL;
const key = process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

// Only the new publishable key is accepted; never put a server key in this app.
function isConfigured(): boolean {
  try {
    const parsed = new URL(url ?? '');
    return parsed.protocol === 'https:' && !!parsed.hostname && !parsed.username && !parsed.password && Boolean(key?.startsWith('sb_publishable_'));
  } catch { return false; }
}
const configured = isConfigured();

export const supabase = configured ? createClient(url!, key!, {
  auth: {
    storage: {
      getItem: (name) => SecureStore.getItemAsync(name),
      setItem: (name, value) => SecureStore.setItemAsync(name, value),
      removeItem: (name) => SecureStore.deleteItemAsync(name),
    },
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: false,
    lock: processLock,
  },
}) : null;

export function authError(error: unknown): string {
  const code = typeof error === 'object' && error !== null && 'code' in error ? error.code : '';
  if (code === 'invalid_credentials') return 'The email or password is incorrect.';
  if (code === 'email_not_confirmed') return 'Confirm your email first, then return here to sign in.';
  if (code === 'weak_password') return 'Choose a stronger password that meets the project password requirements.';
  if (code === 'over_request_rate_limit' || code === 'over_email_send_rate_limit') return 'Too many attempts. Please wait a little and try again.';
  if (code === 'user_already_exists') return 'Try signing in with this email instead.';
  return 'We could not complete that request. Check your connection and try again. If it continues, restart the app.';
}
