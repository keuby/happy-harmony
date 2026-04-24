// REST layer. Thin wrapper around @ohos.net.http providing base URL
// resolution, X-Happy-Client header, and optional bearer token injection.
// WebSocket / LiveKit signalling lives in api/socket.ets (to be added in
// Phase 1b).
//
// ArkTS strict mode pushed us to two workarounds worth calling out:
//   - No indexed access on interface fields, so the bearer-token branch
//     picks between two full HttpHeaderMap literals instead of mutating
//     one in place.
//   - No untyped object literals, so empty response bodies surface as a
//     thrown ApiError rather than a silent `{}`.

import http from '@ohos.net.http';
import { BusinessError } from '@kit.BasicServicesKit';

import { getServerUrl } from './serverConfig';

const CLIENT_VERSION = '1.0.0';

export function getHappyClientId(): string {
  return `harmony/${CLIENT_VERSION}`;
}

let bearerToken: string = '';

export function setBearerToken(token: string): void {
  bearerToken = token;
}

export function clearBearerToken(): void {
  bearerToken = '';
}

interface HttpHeaderMap {
  'Content-Type': string;
  'X-Happy-Client': string;
  'Authorization'?: string;
}

function buildHeaders(): HttpHeaderMap {
  if (bearerToken !== '') {
    const h: HttpHeaderMap = {
      'Content-Type': 'application/json',
      'X-Happy-Client': getHappyClientId(),
      'Authorization': `Bearer ${bearerToken}`,
    };
    return h;
  }
  const h: HttpHeaderMap = {
    'Content-Type': 'application/json',
    'X-Happy-Client': getHappyClientId(),
  };
  return h;
}

export interface ApiResponse<T> {
  status: number;
  body: T;
}

export class ApiError extends Error {
  readonly status: number;
  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

async function request<T>(
  method: http.RequestMethod,
  path: string,
  body: Object | null,
): Promise<ApiResponse<T>> {
  const url = `${getServerUrl()}${path}`;
  const req = http.createHttp();
  try {
    const options: http.HttpRequestOptions = {
      method: method,
      header: buildHeaders(),
      extraData: body !== null ? JSON.stringify(body) : '',
      readTimeout: 10000,
      connectTimeout: 10000,
      expectDataType: http.HttpDataType.STRING,
    };
    const resp = await req.request(url, options);
    const raw: string = typeof resp.result === 'string' ? resp.result : '';
    if (resp.responseCode < 200 || resp.responseCode >= 300) {
      throw new ApiError(`HTTP ${resp.responseCode} on ${method} ${path}: ${raw}`, resp.responseCode);
    }
    if (raw === '') {
      throw new ApiError(`empty response body on ${method} ${path}`, resp.responseCode);
    }
    const parsed = JSON.parse(raw) as T;
    const result: ApiResponse<T> = { status: resp.responseCode, body: parsed };
    return result;
  } catch (e) {
    if (e instanceof ApiError) throw e;
    const err = e as BusinessError;
    const msg = err.message !== undefined ? err.message : JSON.stringify(e);
    throw new ApiError(`network error on ${method} ${path}: ${msg}`, 0);
  } finally {
    req.destroy();
  }
}

export function post<T>(path: string, body: Object): Promise<ApiResponse<T>> {
  return request<T>(http.RequestMethod.POST, path, body);
}

export function httpGet<T>(path: string): Promise<ApiResponse<T>> {
  return request<T>(http.RequestMethod.GET, path, null);
}
