const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),ts=require('typescript');
const moduleRef={exports:{}};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,'../src/lib/trafficRoutes.ts'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,{module:moduleRef,exports:moduleRef.exports,setTimeout,clearTimeout});
const {createTrafficRouter,trafficDelayMillis,fastestRouteId}=moduleRef.exports;
const origin={lat:47.9186,lng:106.9177},destination={lat:47.94,lng:106.98};
const route=(durationMillis=1620000,staticDurationMillis=1140000)=>({path:[origin,{lat:47.93,lng:106.94},destination],durationMillis,staticDurationMillis,distanceMeters:13800});
function router(compute,clock=Date.now,timeout=100){return createTrafficRouter(async()=>({Route:{computeRoutes:compute}}),clock,timeout)}

test('traffic optimal, alternatives, minimal fields, fastest is not necessarily first or shortest',async()=>{
 let request;
 const run=router(async value=>{request=value;return {routes:[{...route(1920000),distanceMeters:12100},route()]}});
 const {routes}=await run(origin,destination);
 assert.equal(request.routingPreference,'TRAFFIC_AWARE_OPTIMAL');assert.equal(request.travelMode,'DRIVING');
 assert.equal(request.computeAlternativeRoutes,true);assert.equal(request.departureTime,undefined);
 assert.equal(request.extraComputations[0],'TRAFFIC_ON_POLYLINE');assert(request.fields.includes('speedPaths'));
 assert.equal(routes[0].distanceMeters,13800);assert.equal(fastestRouteId(routes),routes[0].id);
 assert.equal(trafficDelayMillis(routes[0]),480000);
});
test('same coordinates deduplicate concurrent and repeated calls, cache expires without polling',async()=>{
 let calls=0,now=100;
 const run=router(async()=>{calls++;return {routes:[route()]}},()=>now);
 await Promise.all([run(origin,destination),run({...origin},{...destination})]);
 await run(origin,destination);assert.equal(calls,1);
 now+=120001;await run(origin,destination);assert.equal(calls,2);
 await run(destination,origin);assert.equal(calls,3);
});
test('traffic failures fall back once to normal driving; never present static ETA as live traffic',async()=>{
 const requests=[];
 const run=router(async req=>{requests.push(req);if(requests.length===1)throw Error('Quota/network');return {routes:[route()]}});
 const {routes}=await run(origin,destination);
 assert.equal(requests.length,2);assert.equal(requests[1].routingPreference,'TRAFFIC_UNAWARE');
 assert.equal(routes[0].trafficAware,false);assert.equal(trafficDelayMillis(routes[0]),undefined);
 await run(origin,destination);assert.equal(requests.length,2);
});
test('provider fallback and missing duration data do not invent traffic delay or fastest route',async()=>{
 const {routes}=await router(async()=>({routes:[route(undefined,undefined)],fallbackInfo:{routingMode:'TRAFFIC_UNAWARE'}}))(origin,destination);
 assert.equal(routes[0].trafficAware,false);assert.equal(trafficDelayMillis(routes[0]),undefined);
 const missing={...routes[0],durationMillis:undefined,staticDurationMillis:undefined,trafficDurationMillis:undefined};
 assert.equal(fastestRouteId([missing]),undefined);assert.equal(trafficDelayMillis(missing),undefined);
 assert.equal(trafficDelayMillis({...missing,trafficDurationMillis:100,staticDurationMillis:200}),0);
});
test('no alternatives, short/long trips and optional segment data remain valid',async()=>{
 for(const duration of [120000,7200000]){
  const {routes}=await router(async()=>({routes:[{...route(duration),speedPaths:[{path:[origin,destination],speed:'SLOW'},{path:[origin],speed:'TRAFFIC_JAM'},{path:[origin,destination],speed:'UNKNOWN'}]}]}))(origin,destination);
  assert.equal(routes.length,1);assert.equal(routes[0].durationMillis,duration);assert.equal(routes[0].speedPaths.length,1);
 }
});
test('timeouts are bounded and a hanging traffic request can fall back',async()=>{
 let calls=0;
 const {routes}=await router(async()=>{if(++calls===1)return new Promise(()=>{});return {routes:[route()]}},Date.now,5)(origin,destination);
 assert.equal(calls,2);assert.equal(routes[0].trafficAware,false);
});
test('no route and repeated failures have cooldown; invalid endpoints never call Google',async()=>{
 let calls=0,now=0;
 const run=router(async()=>{calls++;return {routes:[]}},()=>now);
 await assert.rejects(run(origin,destination));await assert.rejects(run(origin,destination));assert.equal(calls,2);
 await assert.rejects(run({lat:NaN,lng:0},destination));await assert.rejects(run(origin,{lat:91,lng:0}));assert.equal(calls,2);
 now=15001;await assert.rejects(run(origin,destination));assert.equal(calls,4);
});
test('malformed paths are rejected without drawing straight-line replacements',async()=>{
 await assert.rejects(router(async()=>({routes:[{...route(),path:[origin,{lat:Infinity,lng:100}]}]}))(origin,destination));
});
