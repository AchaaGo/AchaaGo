// Browser lifecycle regression with isolated API, WebSocket and Maps fixtures.
const assert=require('node:assert/strict');
let chromium;try{({chromium}=require('@playwright/test'))}catch{({chromium}=require('playwright'))}
const url=process.env.BOOKING_URL||'http://64.119.31.106:8187';
(async()=>{
 const browser=await chromium.launch({headless:true,channel:process.env.BOOKING_BROWSER||undefined});
 try{
  const page=await browser.newPage({viewport:{width:390,height:844}});
  await page.addInitScript(()=>{
   window.__lines=[];window.__pending=[];window.__calls=0;
   window.google={maps:{
    Map:class{addListener(){}fitBounds(bounds){window.__bounds=bounds.points}panTo(){}},
    Marker:class{setMap(){}setPosition(){}},
    Polyline:class{constructor(options){this.value={...options,active:true};window.__lines.push(this.value)}setMap(map){this.value.active=!!map}},
    LatLngBounds:class{constructor(){this.points=[]}extend(p){this.points.push(p)}},SymbolPath:{CIRCLE:0},
    importLibrary:async()=>({Route:{computeRoutes:request=>{window.__calls++;if(window.__fail)return Promise.reject(Error('fixture failure'));if(window.__auto)return Promise.resolve({routes:[{path:[request.origin,{lat:47.94,lng:106.91},request.destination]}]});return new Promise(resolve=>window.__pending.push({resolve,request}))}}}),
   }};
  });
  let order={id:'fixture',status:'assigned',service_name:'Портер',pickup:{lat:38.5,lng:-120.2,address:'Авах'},dropoff:{lat:43.252,lng:-126.453,address:'Хүргэх'},distance_km:7,duration_minutes:15,polyline:'_p~iF~ps|U_ulLnnqC_mqNvxq`@'};
  await page.route(url+'/api/t/**',r=>r.fulfill({json:order}));
  let socket;
  await page.routeWebSocket('**/ws/tracking/**',ws=>{socket=ws});
  await page.goto(url+'/t/route-fixture');
  await page.waitForFunction(()=>window.__lines.filter(l=>l.active).length===2);
  assert.equal(await page.evaluate(()=>window.__calls),0);
  assert.deepEqual(await page.evaluate(()=>window.__lines.find(l=>l.active).path[1]),{lat:40.7,lng:-120.95});
  assert(await page.evaluate(()=>window.__bounds.some(p=>p.lat===40.7)));
  const count=await page.evaluate(()=>window.__lines.length);
  const send=change=>{order={...order,...change};socket.send(JSON.stringify({type:'snapshot',order}))};
  send({driver:{name:'Туршилт',location:{lat:40,lng:-121}}});
  await page.getByText('Туршилт',{exact:true}).waitFor();
  assert.equal(await page.evaluate(()=>window.__lines.length),count);
  send({polyline:null,pickup:{lat:47.91,lng:106.90,address:'Авах 1'},dropoff:{lat:47.92,lng:106.92,address:'Хүргэх 1'}});
  await page.waitForFunction(()=>window.__pending.length===1);
  assert.equal(await page.evaluate(()=>window.__lines.filter(l=>l.active).length),0);
  send({dropoff:{lat:47.93,lng:106.93,address:'Хүргэх 2'}});
  await page.waitForFunction(()=>window.__pending.length===2);
  await page.evaluate(()=>window.__pending[1].resolve({routes:[{path:[{lat:47.91,lng:106.90},{lat:47.94,lng:106.90},{lat:47.93,lng:106.93}]}]}));
  await page.waitForFunction(()=>window.__lines.filter(l=>l.active).length===2);
  await page.evaluate(()=>window.__pending[0].resolve({routes:[{path:[{lat:47.91,lng:106.90},{lat:47.95,lng:106.90},{lat:47.92,lng:106.92}]}]}));
  assert.equal(await page.evaluate(()=>window.__lines.find(l=>l.active).path.at(-1).lat),47.93);
  await page.evaluate(()=>window.__fail=true);
  send({dropoff:{lat:47.95,lng:106.94,address:'Хүргэх 3'}});
  await page.getByText('Авто замын маршрут олдсонгүй. Дахин оролдоно уу.',{exact:true}).waitFor();
  assert.equal(await page.evaluate(()=>window.__lines.filter(l=>l.active).length),0);
  await page.evaluate(()=>{window.__fail=false;window.__auto=true});
  await page.getByRole('button',{name:'Дахин оролдох',exact:true}).click();
  await page.waitForFunction(()=>window.__lines.filter(l=>l.active).length===2);
  assert.equal(await page.evaluate(()=>window.__lines.find(l=>l.active).path.at(-1).lat),47.95);
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  console.log('PASS: encoded route, full-route bounds, no reroute on driver updates, stale response rejection, route clearing, failure/retry, mobile overflow');
 }finally{await browser.close()}
})().catch(error=>{console.error(error);process.exitCode=1});
