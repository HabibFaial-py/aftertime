import { supabase } from './supabase';

const DEFAULT_TIMEOUT_MS = 10000;

export class ApiError extends Error {
  constructor(public readonly kind: 'config' | 'session' | 'unauthorized' | 'network' | 'response' | 'timeout') {
    super(kind);
  }
}

function apiBaseUrl(): string {
  try {
    const url = new URL(process.env.EXPO_PUBLIC_API_BASE_URL ?? '');
    const host = url.hostname;
    const privateIp = /^(10\.(\d{1,3}\.){2}\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})$/.test(host) &&
      host.split('.').every((part) => Number(part) <= 255);
    const localHttp = __DEV__ && url.protocol === 'http:' && (privateIp || host === 'localhost' || host === '127.0.0.1');
    if ((url.protocol !== 'https:' && !localHttp) || !host || url.username || url.password || url.search || url.hash || (url.pathname !== '/' && url.pathname !== '')) throw new Error();
    return url.origin;
  } catch {
    throw new ApiError('config');
  }
}

export async function getAuthenticatedUser(expectedUserId: string, signal: AbortSignal, timeoutMs = DEFAULT_TIMEOUT_MS): Promise<{ id: string }> {
  const client = supabase;
  if (!client) throw new ApiError('session');
  const baseUrl = apiBaseUrl();
  const controller = new AbortController();
  let timedOut = false;
  const cancel = () => controller.abort();
  signal.addEventListener('abort', cancel);
  if (signal.aborted) controller.abort();
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    // getSession may refresh an expired token. The deadline also covers that step.
    const timeout = new Promise<never>((_, reject) => {
      timer = setTimeout(() => { timedOut = true; controller.abort(); reject(new ApiError('timeout')); }, timeoutMs);
    });
    const request = async () => {
      const { data, error } = await client.auth.getSession();
      const session = data.session;
      if (controller.signal.aborted) throw new ApiError('network');
      if (error || !session?.access_token || session.user.id !== expectedUserId || !session.expires_at || session.expires_at * 1000 <= Date.now()) throw new ApiError('session');
      const response = await fetch(`${baseUrl}/v1/auth/me`, {
        headers: { Authorization: `Bearer ${session.access_token}` },
        signal: controller.signal,
        redirect: 'error',
      });
      if (response.status === 401 || response.status === 403) throw new ApiError('unauthorized');
      if (response.status !== 200) throw new ApiError('response');
      const result: unknown = await response.json();
      if (typeof result !== 'object' || result === null || !('id' in result) || result.id !== expectedUserId) throw new ApiError('response');
      return { id: expectedUserId };
    };
    return await Promise.race([request(), timeout]);
  } catch (error) {
    if (timedOut) throw new ApiError('timeout');
    if (error instanceof ApiError) throw error;
    throw new ApiError('network');
  } finally {
    if (timer) clearTimeout(timer);
    signal.removeEventListener('abort', cancel);
  }
}
