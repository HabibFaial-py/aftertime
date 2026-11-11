import { Session } from '@supabase/supabase-js';
import { createContext, PropsWithChildren, useContext, useEffect, useState } from 'react';
import { AppState } from 'react-native';
import { supabase } from './supabase';

type AuthState = { session: Session | null; expired: boolean; loading: boolean; error: string; retry: () => void };
const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: PropsWithChildren) {
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(!!supabase);
  const [error, setError] = useState(supabase ? '' : 'Add the mobile Supabase URL and publishable key, then restart Expo.');
  const [attempt, setAttempt] = useState(0);
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    if (!session?.expires_at) return;
    const timer = setTimeout(() => setNow(Date.now()), Math.min(2147483647, Math.max(0, session.expires_at * 1000 - Date.now()) + 50));
    return () => clearTimeout(timer);
  }, [session]);

  useEffect(() => {
    const client = supabase;
    if (!client) return;
    let active = true;
    let receivedEvent = false;
    const { data: { subscription } } = client.auth.onAuthStateChange((_event, next) => {
      // Do not await other Auth calls inside this callback (the SDK holds a lock).
      receivedEvent = true;
      if (active) { setNow(Date.now()); setSession(next); setLoading(false); }
    });
    client.auth.getSession().then(({ data, error: failure }) => {
      if (!active) return;
      if (failure) setError('Your session could not be restored. Check your connection and retry.');
      else if (!receivedEvent) { setNow(Date.now()); setSession(data.session); }
    }).catch(() => {
      if (active) setError('Secure session storage could not be read. Restart the app and retry.');
    }).finally(() => { if (active) setLoading(false); });
    const refresh = (state: string | null | undefined) => {
      const action = state === 'active' ? client.auth.startAutoRefresh() : client.auth.stopAutoRefresh();
      void action.catch(() => {
        if (active) setError('Session refresh failed. Check your connection and retry.');
      });
    };
    refresh(AppState.currentState);
    const listener = AppState.addEventListener('change', (state) => { setNow(Date.now()); refresh(state); });
    return () => {
      active = false;
      subscription.unsubscribe();
      listener.remove();
      void client.auth.stopAutoRefresh().catch(() => {});
    };
  }, [attempt]);

  const expired = !!session && (!session.expires_at || session.expires_at * 1000 <= now);
  function retry() {
    if (!supabase) return;
    setLoading(true);
    setError('');
    setAttempt((n) => n + 1);
  }
  return <AuthContext.Provider value={{ session: expired ? null : session, expired, loading, error, retry }}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const value = useContext(AuthContext);
  if (!value) throw new Error('AuthProvider is required');
  return value;
}
