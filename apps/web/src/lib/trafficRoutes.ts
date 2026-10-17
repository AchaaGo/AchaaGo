import type {RoutePoint} from './roadRoute';

export type TrafficRoute = {
  id: string;
  origin: RoutePoint;
  destination: RoutePoint;
  path: RoutePoint[];
  durationMillis?: number;
  trafficDurationMillis?: number;
  staticDurationMillis?: number;
  distanceMeters?: number;
  trafficAware: boolean;
  speedPaths: {path: RoutePoint[]; speed: 'NORMAL' | 'SLOW' | 'TRAFFIC_JAM'}[];
  warnings: string[];
};
export type RouteResult = {routes: TrafficRoute[]; calculatedAt: number};
type ProviderRoute = {
  path?: RoutePoint[];
  durationMillis?: number;
  staticDurationMillis?: number;
  distanceMeters?: number;
  speedPaths?: {path: RoutePoint[]; speed?: string}[];
  warnings?: string[];
};
type Request = {
  origin: RoutePoint; destination: RoutePoint; travelMode: 'DRIVING';
  routingPreference: 'TRAFFIC_AWARE_OPTIMAL' | 'TRAFFIC_UNAWARE';
  computeAlternativeRoutes: boolean; polylineQuality: 'HIGH_QUALITY';
  extraComputations?: ['TRAFFIC_ON_POLYLINE']; fields: string[];
};
type RoutesLibrary = {Route: {computeRoutes(request: Request): Promise<{
  routes?: ProviderRoute[]; fallbackInfo?: {routingMode?: string};
}>}};

export function validPoint(point: RoutePoint | null | undefined): point is RoutePoint {
  return !!point && Number.isFinite(point.lat) && Number.isFinite(point.lng)
    && Math.abs(point.lat) <= 90 && Math.abs(point.lng) <= 180;
}
export function routeKey(origin: RoutePoint | null, destination: RoutePoint | null): string {
  return validPoint(origin) && validPoint(destination)
    ? `${origin.lat},${origin.lng}:${destination.lat},${destination.lng}` : '';
}
function finite(value: number | undefined) {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : undefined;
}
function pathOf(path: RoutePoint[] | undefined): RoutePoint[] {
  if (!path || path.length < 2 || !path.every(validPoint)) return [];
  return path.map(({lat,lng}) => ({lat,lng}));
}
export function trafficDelayMillis(route: TrafficRoute): number | undefined {
  return route.trafficDurationMillis !== undefined && route.staticDurationMillis !== undefined
    ? Math.max(0, route.trafficDurationMillis - route.staticDurationMillis) : undefined;
}
export function fastestRouteId(routes: TrafficRoute[]): string | undefined {
  // Missing durations never imply zero travel time.
  return [...routes].filter(route => route.durationMillis !== undefined)
    .sort((a,b) => a.durationMillis! - b.durationMillis!)[0]?.id;
}
export function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  return new Promise((resolve,reject) => {
    const timer = setTimeout(() => reject(new Error('Route timeout')), ms);
    promise.then(value => {clearTimeout(timer); resolve(value)}, error => {clearTimeout(timer); reject(error)});
  });
}

/** One shared in-flight request per coordinate pair; short-lived, memory-only cache.
 * No polling, persistent location storage, or credentials outside the Maps SDK.
 * Injected clock/SDK allow deterministic tests without billable Google requests.
 */
export function createTrafficRouter(load: () => Promise<RoutesLibrary>, now = Date.now, timeoutMs = 8000) {
  const cache = new Map<string, {expires: number; promise: Promise<RouteResult>}>();
  return (origin: RoutePoint, destination: RoutePoint): Promise<RouteResult> => {
    const key = routeKey(origin,destination);
    if (!key) return Promise.reject(new Error('Invalid endpoints'));
    const cached = cache.get(key);
    if (cached && cached.expires > now()) return cached.promise;
    for (const [key,entry] of cache) if (entry.expires <= now()) cache.delete(key);
    // Evict only settled entries, never an in-flight request.
    if (cache.size >= 20) {
      const oldest = [...cache].find(([,entry]) => Number.isFinite(entry.expires));
      if (oldest) cache.delete(oldest[0]);
    }
    const entry = {expires: Infinity, promise: Promise.resolve(null as unknown as RouteResult)};
    async function request(traffic: boolean): Promise<RouteResult> {
      const result = await withTimeout((async () => {
        const {Route} = await load();
        return Route.computeRoutes({origin, destination, travelMode:'DRIVING',
          routingPreference:traffic ? 'TRAFFIC_AWARE_OPTIMAL' : 'TRAFFIC_UNAWARE',
          // Omitted departureTime means NOW at Google, avoiding a timestamp
          // that has slipped into the past during slow mobile transmission.
          computeAlternativeRoutes:true, polylineQuality:'HIGH_QUALITY',
          ...(traffic ? {extraComputations:['TRAFFIC_ON_POLYLINE'] as ['TRAFFIC_ON_POLYLINE']} : {}),
          fields:['path','durationMillis','staticDurationMillis','distanceMeters','warnings', ...(traffic ? ['speedPaths'] : [])],
        });
      })(), timeoutMs);
      const trafficAware = traffic && (!result.fallbackInfo || result.fallbackInfo.routingMode === 'TRAFFIC_AWARE');
      const routes = (result.routes ?? []).flatMap((value,index): TrafficRoute[] => {
        const path = pathOf(value.path);
        if (!path.length) return [];
        const durationMillis = finite(value.durationMillis);
        return [{id:`${key}:${index}`, origin:{...origin}, destination:{...destination}, path,
          durationMillis, staticDurationMillis:finite(value.staticDurationMillis),
          trafficDurationMillis:trafficAware ? durationMillis : undefined,
          distanceMeters:finite(value.distanceMeters), trafficAware,
          warnings:value.warnings ?? [],
          speedPaths:trafficAware ? (value.speedPaths ?? []).flatMap(segment => {
            const path = pathOf(segment.path);
            return path.length && (segment.speed === 'NORMAL' || segment.speed === 'SLOW' || segment.speed === 'TRAFFIC_JAM')
              ? [{path,speed:segment.speed}] : [];
          }) : [],
        }];
      });
      if (!routes.length) throw new Error('No route');
      routes.sort((a,b) => (a.durationMillis ?? Infinity) - (b.durationMillis ?? Infinity));
      return {routes,calculatedAt:now()};
    }
    entry.promise = request(true).catch(() => request(false)).then(result => {
      entry.expires = now() + (result.routes.every(route => route.trafficAware) ? 120000 : 30000);
      return result;
    }, error => {entry.expires = now() + 15000; throw error});
    cache.set(key,entry);
    return entry.promise;
  };
}

const routers = new WeakMap<object, ReturnType<typeof createTrafficRouter>>();
export function trafficRoutes(maps: typeof google.maps, origin: RoutePoint, destination: RoutePoint) {
  let router = routers.get(maps);
  if (!router) {
    router = createTrafficRouter(() => maps.importLibrary('routes') as unknown as Promise<RoutesLibrary>);
    routers.set(maps,router);
  }
  return router(origin,destination);
}
