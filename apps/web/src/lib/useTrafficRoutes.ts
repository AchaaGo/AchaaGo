'use client';
import {useEffect,useMemo,useState} from 'react';
import {loadGoogleMaps} from './googleMaps';
import {decodeRoutePath,type RoutePoint} from './roadRoute';
import {routeKey,trafficRoutes,withTimeout,type TrafficRoute} from './trafficRoutes';

const EMPTY: TrafficRoute[] = [];
export function useTrafficRoutes(origin: RoutePoint | null, destination: RoutePoint | null, encoded?: string | null) {
  const key = routeKey(origin,destination);
  const [state,setState] = useState<{key:string; routes:TrafficRoute[]; status:'loading'|'ready'|'error'}>({key:'',routes:EMPTY,status:'loading'});
  const [selectedId,setSelectedId] = useState<string>();
  const [retry,setRetry] = useState(0);
  useEffect(() => {
    if (!key || !origin || !destination) return;
    let cancelled = false;
    setState({key,routes:EMPTY,status:'loading'});
    setSelectedId(undefined);
    const apiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY;
    const request = apiKey ? withTimeout(loadGoogleMaps(apiKey),8000).then(maps => trafficRoutes(maps,origin,destination))
      : Promise.reject(new Error('Maps unavailable'));
    request.then(result => {
      if (!cancelled) setState({key,routes:result.routes,status:'ready'});
    }, () => {if (!cancelled) setState({key,routes:EMPTY,status:'error'})});
    return () => {cancelled = true};
    // Coordinate identity is intentional: quoting/loaders/rerenders must not refetch.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  },[key,retry]);
  const fallback = useMemo((): TrafficRoute[] => {
    if (!key || !origin || !destination || !encoded) return EMPTY;
    try {return [{id:`${key}:quote`,origin,destination,path:decodeRoutePath(encoded),trafficAware:false,speedPaths:[],warnings:[]}]} catch {return EMPTY}
    // eslint-disable-next-line react-hooks/exhaustive-deps
  },[key,encoded]);
  const status = !key ? 'idle' : state.key !== key ? 'loading' : state.status;
  const routes = status === 'ready' ? state.routes : status === 'error' ? fallback : EMPTY;
  const selectedRoute = routes.find(route => route.id === selectedId) ?? routes[0];
  return {routes,selectedRoute,status:routes.length ? 'ready' as const : status,
    selectRoute:setSelectedId, retry:() => setRetry(value => value+1)};
}
