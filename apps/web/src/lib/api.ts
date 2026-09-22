import {mn} from './messages';

export class ApiError extends Error { constructor(public code:string, public status:number){super(mn.errors[code] || 'Алдаа гарлаа. Дахин оролдоно уу.')} }

export async function api<T>(path:string, init:RequestInit = {}):Promise<T> {
  try {
    const response = await fetch('/api'+path, {credentials:'include', cache:'no-store', ...init,
      headers:{'Content-Type':'application/json', ...(init.headers || {})}});
    const body = await response.json().catch(()=>({detail:'UNKNOWN'}));
    if (!response.ok) throw new ApiError(body.detail || 'UNKNOWN', response.status);
    return body as T;
  } catch (error) {
    if (error instanceof ApiError) throw error;
    throw new ApiError('NETWORK', 0);
  }
}

export const money = (value:number) => new Intl.NumberFormat('mn-MN').format(value)+'₮';
export const phoneFmt = (value:string) => value.replace(/\D/g,'').slice(0,8).replace(/(\d{4})(?=\d)/,'$1 ');
export const uuid = () => crypto.randomUUID();

export type Service = {id:string;code:string;name_mn:string;description_mn:string;icon:'truck'|'package';base_fare:number;per_km_rate:number;is_active:boolean;sort_order:number};
export type Point = {lat:number;lng:number;address:string};
export type Price = {service:Service;breakdown:{total:number;service_name:string;base_fare:number;distance_fare:number;loader_fare:number;night_surcharge:number}};
export type Quote = {distance_km:number;duration_minutes:number;polyline?:string;prices:Price[];loader_rate:number;approximate:boolean;quote_token:string};
export type Driver = {id?:string;name?:string;phone?:string;rating?:number;plate_number?:string;location?:{lat:number;lng:number};location_fresh?:boolean;last_seen?:string};
export type Order = {id:string;status:string;service_id?:string;service_name:string;pickup:Point;dropoff:Point;distance_km:number;duration_minutes:number;loaders?:number;payment_method?:'cash'|'qpay';payment_status?:string;total_price?:number;tracking_token?:string;price_breakdown?:Record<string,number|string>;driver?:Driver|null;can_cancel?:boolean;rating?:number|null;created_at:string;updated_at:string};
