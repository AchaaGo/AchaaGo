import {normalizeWords,pointFromWords,type WordSuggestion} from '@/lib/what3words';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
const limits = new Map<string,{count:number; until:number}>();
const response = (body:unknown,status=200) => Response.json(body,{status,headers:{'Cache-Control':'no-store'}});
const error = (detail:string,status:number) => response({detail},status);

// A Next route outside /api avoids the existing nginx /api -> FastAPI mapping.
// Keep the provider key server-only and reuse the existing session authority.
export async function POST(request: Request) {
  const origin = request.headers.get('origin');
  const host = request.headers.get('host');
  try {if (!origin || new URL(origin).host !== host) return error('W3W_FORBIDDEN',403)}
  catch {return error('W3W_FORBIDDEN',403)}
  if (Number(request.headers.get('content-length')) > 1024) return error('W3W_INVALID',400);
  let input:{action?:unknown;words?:unknown};
  try {
    const raw = await request.text();
    if (raw.length > 1024) return error('W3W_INVALID',400);
    input = JSON.parse(raw);
  } catch {return error('W3W_INVALID',400)}
  const words = normalizeWords(input?.words);
  if (!words || (input?.action !== 'suggest' && input?.action !== 'resolve')) return error('W3W_INVALID',400);
  const cookie = request.headers.get('cookie')?.split(';').find(part => part.trim().startsWith('ag_access='))?.trim();
  if (!cookie) return error('LOGIN_REQUIRED',401);
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(),10000);
  try {
    const auth = await fetch(`${process.env.API_INTERNAL_URL || 'http://127.0.0.1:8188'}/auth/me`,{
      headers:{cookie},cache:'no-store',signal:controller.signal,redirect:'error',
    });
    if (auth.status === 401 || auth.status === 403) return error('LOGIN_REQUIRED',401);
    if (!auth.ok) return error('W3W_UNAVAILABLE',503);
    const user = await auth.json();
    if (typeof user?.id !== 'string') return error('LOGIN_REQUIRED',401);
    const now = Date.now();
    for (const [id,entry] of limits) if (entry.until <= now) limits.delete(id);
    const entry = limits.get(user.id) ?? {count:0,until:now+60000};
    if (entry.count >= 40 || (!limits.has(user.id) && limits.size >= 1000)) return error('W3W_QUOTA',429);
    entry.count++; limits.set(user.id,entry);
    const key = process.env.WHAT3WORDS_API_KEY;
    if (!key) return error('W3W_UNAVAILABLE',503);
    const url = new URL(`https://api.what3words.com/v3/${input.action === 'suggest' ? 'autosuggest' : 'convert-to-coordinates'}`);
    url.searchParams.set(input.action === 'suggest' ? 'input' : 'words',words);
    if (input.action === 'suggest') url.searchParams.set('clip-to-country','MN');
    const result = await fetch(url,{headers:{'X-Api-Key':key},cache:'no-store',signal:controller.signal,redirect:'error'});
    const data = await result.json();
    if (!result.ok || data.error) {
      if (result.status === 402 || result.status === 429 || data.error?.code === 'QuotaExceeded') return error('W3W_QUOTA',429);
      if (data.error?.code === 'BadWords') return error('W3W_NOT_FOUND',404);
      return error('W3W_UNAVAILABLE',503);
    }
    if (input.action === 'resolve') {
      const point = pointFromWords(data);
      return point ? response({point}) : error('W3W_NOT_FOUND',404);
    }
    const suggestions:WordSuggestion[] = Array.isArray(data.suggestions) ? data.suggestions.flatMap((value:Partial<WordSuggestion>) => {
      const words = normalizeWords(value?.words);
      return words ? [{words,nearestPlace:typeof value.nearestPlace === 'string' ? value.nearestPlace : '',country:typeof value.country === 'string' ? value.country : ''}] : [];
    }).slice(0,3) : [];
    return response({suggestions});
  } catch {return error(controller.signal.aborted ? 'W3W_TIMEOUT' : 'W3W_UNAVAILABLE',503)}
  finally {clearTimeout(timer)}
}
