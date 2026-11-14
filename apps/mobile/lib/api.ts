import { supabase } from './supabase';

const DEFAULT_TIMEOUT_MS = 10000;

export class ApiError extends Error {
  constructor(public readonly kind: 'config' | 'session' | 'unauthorized' | 'network' | 'response' | 'timeout' | 'cancelled', public readonly status?: number) {
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

type RequestOptions<T> = {
  expectedUserId: string;
  signal: AbortSignal;
  path: string;
  method?: 'GET' | 'POST';
  body?: unknown;
  expectedStatuses: readonly number[];
  parse: (value: unknown) => T;
  timeoutMs?: number;
};

export async function authenticatedRequest<T>(options: RequestOptions<T>): Promise<T> {
  const client = supabase;
  if (!client) throw new ApiError('session');
  const baseUrl = apiBaseUrl();
  const { expectedUserId, signal, path, method = 'GET', body, expectedStatuses, parse, timeoutMs = DEFAULT_TIMEOUT_MS } = options;
  if (!path.startsWith('/v1/') || path.includes('\\') || path.includes('#')) throw new ApiError('config');
  const controller = new AbortController();
  let timedOut = false;
  let rejectCancelled: (error: ApiError) => void = () => {};
  const cancelled = new Promise<never>((_, reject) => { rejectCancelled = reject; });
  const cancel = () => { controller.abort(); rejectCancelled(new ApiError('cancelled')); };
  signal.addEventListener('abort', cancel);
  if (signal.aborted) cancel();
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
      const response = await fetch(`${baseUrl}${path}`, {
        method,
        headers: { Authorization: `Bearer ${session.access_token}`, ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}) },
        ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
        signal: controller.signal,
        redirect: 'error',
      });
      if (response.status === 401 || response.status === 403) throw new ApiError('unauthorized', response.status);
      if (!expectedStatuses.includes(response.status)) throw new ApiError('response', response.status);
      try {
        const result: unknown = response.status === 204 || response.status === 205 ? undefined : await response.json();
        return parse(result);
      } catch { throw new ApiError('response'); }
    };
    return await Promise.race([request(), timeout, cancelled]);
  } catch (error) {
    if (timedOut) throw new ApiError('timeout');
    if (error instanceof ApiError) throw error;
    throw new ApiError('network');
  } finally {
    if (timer) clearTimeout(timer);
    signal.removeEventListener('abort', cancel);
  }
}

export async function getAuthenticatedUser(expectedUserId: string, signal: AbortSignal, timeoutMs = DEFAULT_TIMEOUT_MS): Promise<{ id: string }> {
  return authenticatedRequest({ expectedUserId, signal, timeoutMs, path: '/v1/auth/me', expectedStatuses: [200], parse: (result) => {
    if (typeof result !== 'object' || result === null || !('id' in result) || result.id !== expectedUserId) throw new Error();
    return { id: expectedUserId };
  } });
}
