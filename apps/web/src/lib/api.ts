import {mn} from './messages';

export class ApiError extends Error { constructor(public code:string, public status:number){super(mn.errors[code] || 'Алдаа гарлаа. Дахин оролдоно уу.')} }

// Reads give up after 15 s; writes get 30 s because quotes, orders and QPay wait on
// external providers. The gateway (infra/nginx.conf) also stops waiting at 30 s.
const READ_TIMEOUT = 15000, WRITE_TIMEOUT = 30000;

type RefreshOutcome = 'ok' | 'expired' | 'network';
type Result = {status:number; ok:boolean; body:any};
let refreshing: Promise<RefreshOutcome> | null = null;

/** fetch + JSON with a hard time limit that also covers reading the body.
 *  (Not AbortSignal.timeout: iOS 15 Safari lacks it.) */
async function request(url:string, init:RequestInit, timeout:number):Promise<Result> {
  const controller = new AbortController();
  let timedOut = false;
  const timer = setTimeout(() => { timedOut = true; controller.abort(); }, timeout);
  try {
    const response = await fetch(url, {credentials:'include', cache:'no-store', ...init, signal:controller.signal,
      headers:{'Content-Type':'application/json', ...(init.headers || {})}});
    const body = await response.json().catch(() => ({detail: response.status >= 502 ? 'SERVICE_UNAVAILABLE' : 'UNKNOWN'}));
    return {status:response.status, ok:response.ok, body};
  } catch {
    throw new ApiError(timedOut ? 'TIMEOUT' : 'NETWORK', 0);
  } finally {
    clearTimeout(timer);
  }
}

/** Renews the 15-minute access cookie with the 30-day refresh cookie (path /api/auth).
 *  Parallel callers share one request: the server rotates the refresh token, so racing
 *  refreshes could otherwise log the user out. */
export function refreshSession(): Promise<RefreshOutcome> {
  if (!refreshing) {
    refreshing = request('/api/auth/refresh', {method:'POST', body:'{}'}, READ_TIMEOUT)
      .then(result => result.ok ? 'ok' as const : result.status === 401 ? 'expired' as const : 'network' as const)
      .catch(() => 'network' as const)
      .finally(() => { refreshing = null; });
  }
  return refreshing;
}

export async function api<T>(path:string, init:RequestInit = {}):Promise<T> {
  const method = (init.method || 'GET').toUpperCase();
  const timeout = method === 'GET' ? READ_TIMEOUT : WRITE_TIMEOUT;
  let result:Result;
  try {
    result = await request('/api'+path, init, timeout);
  } catch (error) {
    // Reads are safe to repeat: one quiet retry rides out a dropped mobile connection.
    // Not after a timeout, which already kept the customer waiting 15 s.
    if (method !== 'GET' || (error as ApiError).code !== 'NETWORK') throw error;
    await new Promise(resolve => setTimeout(resolve, 800));
    result = await request('/api'+path, init, timeout);
  }
  // Every page load checks the session with /auth/me after the browser has dropped the
  // 15-minute access cookie, so that call renews too. Only the login calls answer for themselves.
  const renewable = !path.startsWith('/auth/otp/') && path !== '/auth/refresh';
  if (result.status === 401 && renewable && (result.body.detail === 'SESSION_EXPIRED' || result.body.detail === 'LOGIN_REQUIRED')) {
    // The server rejected the request before running it, so repeating it after a refresh
    // is safe (POST /orders also carries its Idempotency-Key).
    const outcome = await refreshSession();
    if (outcome === 'network') throw new ApiError('NETWORK', 0);
    if (outcome === 'ok') result = await request('/api'+path, init, timeout);
  }
  if (!result.ok) throw new ApiError(result.body.detail || 'UNKNOWN', result.status);
  return result.body as T;
}

export const money = (value:number) => new Intl.NumberFormat('mn-MN').format(value)+'₮';
export const phoneFmt = (value:string) => value.replace(/\D/g,'').slice(0,8).replace(/(\d{4})(?=\d)/,'$1 ');
// crypto.randomUUID only exists on HTTPS pages; getRandomValues works everywhere, including
// the current plain-HTTP deployment, where order placement used to throw before sending.
export function uuid() {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; bytes[8] = (bytes[8] & 0x3f) | 0x80;  // RFC 4122 version 4
  const hex = Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
}

export type Service = {id:string;code:string;name_mn:string;description_mn:string;icon:'truck'|'package';base_fare:number;per_km_rate:number;is_active:boolean;sort_order:number};
export type Point = {lat:number;lng:number;address:string};
export type Price = {service:Service;breakdown:{total:number;service_name:string;base_fare:number;distance_fare:number;loader_fare:number;night_surcharge:number}};
export type Quote = {distance_km:number;duration_minutes:number;polyline?:string|null;prices:Price[];loader_rate:number;approximate:boolean;quote_token:string};
export type Driver = {id?:string;name?:string;phone?:string;rating?:number;plate_number?:string;location?:{lat:number;lng:number};location_fresh?:boolean;last_seen?:string};
export type Order = {polyline?:string|null;id:string;status:string;service_id?:string;service_name:string;pickup:Point;dropoff:Point;distance_km:number;duration_minutes:number;loaders?:number;payment_method?:'cash'|'qpay';payment_status?:string;total_price?:number;tracking_token?:string;price_breakdown?:Record<string,number|string>;driver?:Driver|null;can_cancel?:boolean;rating?:number|null;created_at:string;updated_at:string};
