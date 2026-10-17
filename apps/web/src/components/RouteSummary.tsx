'use client';
import {Check} from 'lucide-react';
import {fastestRouteId,trafficDelayMillis,type TrafficRoute} from '@/lib/trafficRoutes';
import {customerCopy as copy} from './customerCopy';

export function routeMetrics(route: TrafficRoute) {
  return [route.durationMillis !== undefined ? `${Math.max(1,Math.ceil(route.durationMillis/60000))} ${copy.routeMinutes}` : '',
    route.distanceMeters !== undefined ? `${(route.distanceMeters/1000).toLocaleString('mn-MN',{maximumFractionDigits:1})} ${copy.routeKilometers}` : ''].filter(Boolean).join(' · ');
}
export function RouteSummary({routes,selectedRoute,status,selectRoute,retry}: {
  routes:TrafficRoute[]; selectedRoute?:TrafficRoute; status:string;
  selectRoute:(id:string)=>void; retry:()=>void;
}) {
  if (status === 'idle') return null;
  if (status === 'loading') return <div className="traffic-summary" role="status">{copy.trafficLoading}</div>;
  if (!selectedRoute) return <div className="traffic-summary" role="status"><span>{copy.roadUnavailable}</span> <button type="button" onClick={retry}>{copy.retry}</button></div>;
  const fastest = fastestRouteId(routes);
  const delay = trafficDelayMillis(selectedRoute);
  const hasColors = selectedRoute.speedPaths.some(segment => segment.speed !== 'NORMAL');
  return <section className="traffic-summary" aria-label={copy.routeTime}>
    <div aria-live="polite" aria-atomic="true">
      <div className="traffic-summary-heading"><strong>{selectedRoute.trafficAware && selectedRoute.id === fastest ? copy.fastestRoute : copy.selectedRoute}</strong><b>{routeMetrics(selectedRoute)}</b></div>
      {!selectedRoute.trafficAware ? <p>{copy.trafficUnavailable}</p> : delay !== undefined && <p>{delay < 60000 ? copy.trafficNormal : `${copy.trafficDelay}: +${Math.ceil(delay/60000)} ${copy.routeMinutes}`}</p>}
    </div>
    {routes.length > 1 && <div className="traffic-options" role="group" aria-label={copy.otherRoutes}>
      {routes.map((route,index) => <button type="button" key={route.id} aria-pressed={route.id === selectedRoute.id} onClick={() => selectRoute(route.id)} aria-label={`${copy.routeOption} ${index+1}: ${routeMetrics(route)}${route.trafficAware && route.id === fastest ? `, ${copy.fastestRoute}` : ''}`}>
        {route.id === selectedRoute.id && <Check size={14} aria-hidden="true"/>}{routeMetrics(route) || `${copy.routeOption} ${index+1}`}
      </button>)}
    </div>}
    {hasColors && <p className="traffic-legend"><span><i data-speed="SLOW"/>{copy.trafficSlow}</span><span><i data-speed="TRAFFIC_JAM"/>{copy.trafficHeavy}</span></p>}
    {selectedRoute.warnings.map((warning,index) => <p key={index}>{warning}</p>)}
    <small>{copy.routeEstimate}</small>
  </section>;
}
