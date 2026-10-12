export type RoutePoint = {lat:number;lng:number};

// Google encoded polylines use 1e5 precision. Reject malformed data instead of
// silently drawing a connection between the endpoints.
export function decodeRoutePath(encoded:string):RoutePoint[] {
  if(!encoded || encoded.length>1000000)throw new Error('Invalid route');
  const points:RoutePoint[]=[];
  let index=0,lat=0,lng=0;
  function delta(){
    let result=0,shift=0,value:number;
    do{
      if(index>=encoded.length||shift>30)throw new Error('Invalid route');
      value=encoded.charCodeAt(index++)-63;
      if(value<0||value>63)throw new Error('Invalid route');
      result+=(value&31)*2**shift;shift+=5;
    }while(value>=32);
    return result%2 ? -(Math.floor(result/2)+1) : result/2;
  }
  while(index<encoded.length){
    lat+=delta();lng+=delta();
    const point={lat:lat/1e5,lng:lng/1e5};
    if(Math.abs(point.lat)>90||Math.abs(point.lng)>180)throw new Error('Invalid route');
    points.push(point);
  }
  if(points.length<2)throw new Error('Empty route');
  return points;
}

// The Maps runtime is newer than the project's typings. Keep the narrow shape
// here rather than upgrading dependencies just to load the Routes library.
type RoutesLibrary={Route:{computeRoutes:(request:{origin:RoutePoint;destination:RoutePoint;travelMode:'DRIVING';polylineQuality:'HIGH_QUALITY';fields:string[]})=>Promise<{routes?:{path?:{lat:number;lng:number}[]}[]}>}};

export async function roadRoute(maps:typeof google.maps,pickup:RoutePoint,dropoff:RoutePoint,encoded?:string|null):Promise<RoutePoint[]> {
  if(encoded)return decodeRoutePath(encoded);
  // https://developers.google.com/maps/documentation/javascript/routes/get-a-route
  const {Route}=await maps.importLibrary('routes') as unknown as RoutesLibrary;
  const result=await Route.computeRoutes({origin:pickup,destination:dropoff,travelMode:'DRIVING',polylineQuality:'HIGH_QUALITY',fields:['path']});
  const path=result.routes?.[0]?.path;
  if(!path||path.length<2)throw new Error('Route not found');
  return path.map(point=>{
    const value={lat:point.lat,lng:point.lng};
    if(!Number.isFinite(value.lat)||!Number.isFinite(value.lng)||Math.abs(value.lat)>90||Math.abs(value.lng)>180)throw new Error('Invalid route');
    return value;
  });
}
