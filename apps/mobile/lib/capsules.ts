import { ApiError, authenticatedRequest } from './api';

export type CreateCapsuleRequest = { title: string; body: string; unlock_at: string };
export type CreateCapsuleResponse = { id: string; title: string; unlock_at: string; created_at: string };
export type CapsuleListItem = CreateCapsuleResponse & { status: 'locked' | 'unlocked' };
export type RevealCapsuleResponse = { id: string; body: string };
export type CancelCapsuleResponse = { id: string; cancelled_at: string };

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const iso = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;
const isTimestamp = (value: unknown): value is string => typeof value === 'string' && iso.test(value) && Number.isFinite(Date.parse(value));
const isUuid = (value: unknown): value is string => typeof value === 'string' && uuid.test(value);

function record(value: unknown, keys: string[]): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) throw new Error();
  const item = value as Record<string, unknown>;
  if (Object.keys(item).length !== keys.length || keys.some((key) => !Object.prototype.hasOwnProperty.call(item, key))) throw new Error();
  return item;
}

function metadata(value: unknown, list = false): CreateCapsuleResponse {
  const item = record(value, ['id', 'title', 'unlock_at', 'created_at', ...(list ? ['status'] : [])]);
  if (!isUuid(item.id) || typeof item.title !== 'string' || !isTimestamp(item.unlock_at) || !isTimestamp(item.created_at)) throw new Error();
  return { id: item.id, title: item.title, unlock_at: item.unlock_at, created_at: item.created_at };
}

function capsulePath(id: string, action: 'reveal' | 'cancel'): string {
  if (!isUuid(id)) throw new ApiError('response');
  return `/v1/capsules/${encodeURIComponent(id)}/${action}`;
}

export function createCapsule(expectedUserId: string, signal: AbortSignal, input: CreateCapsuleRequest): Promise<CreateCapsuleResponse> {
  const body = { title: input.title, body: input.body, unlock_at: input.unlock_at };
  return authenticatedRequest({ expectedUserId, signal, path: '/v1/capsules', method: 'POST', body, expectedStatuses: [201], parse: metadata });
}

export function listCapsules(expectedUserId: string, signal: AbortSignal, limit = 50, offset = 0): Promise<CapsuleListItem[]> {
  if (!Number.isInteger(limit) || limit < 1 || limit > 50 || !Number.isInteger(offset) || offset < 0 || offset > 10000) throw new ApiError('response');
  return authenticatedRequest({ expectedUserId, signal, path: `/v1/capsules?limit=${limit}&offset=${offset}`, expectedStatuses: [200], parse: (value) => {
    if (!Array.isArray(value) || value.length > limit) throw new Error();
    return value.map((entry: unknown) => {
      const item = record(entry, ['id', 'title', 'unlock_at', 'created_at', 'status']);
      if (item.status !== 'locked' && item.status !== 'unlocked') throw new Error();
      return { ...metadata(item, true), status: item.status };
    });
  } });
}

export function revealCapsule(expectedUserId: string, signal: AbortSignal, id: string): Promise<RevealCapsuleResponse> {
  return authenticatedRequest({ expectedUserId, signal, path: capsulePath(id, 'reveal'), expectedStatuses: [200], parse: (value) => {
    const item = record(value, ['id', 'body']);
    if (!isUuid(item.id) || item.id.toLowerCase() !== id.toLowerCase() || typeof item.body !== 'string' || Array.from(item.body).length > 2000) throw new Error();
    return { id: item.id, body: item.body };
  } });
}

export function cancelCapsule(expectedUserId: string, signal: AbortSignal, id: string): Promise<CancelCapsuleResponse> {
  return authenticatedRequest({ expectedUserId, signal, path: capsulePath(id, 'cancel'), method: 'POST', expectedStatuses: [200], parse: (value) => {
    const item = record(value, ['id', 'cancelled_at']);
    if (!isUuid(item.id) || item.id.toLowerCase() !== id.toLowerCase() || !isTimestamp(item.cancelled_at)) throw new Error();
    return { id: item.id, cancelled_at: item.cancelled_at };
  } });
}
