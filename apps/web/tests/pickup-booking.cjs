// Isolated browser regression: all API, Maps SDK and location responses are fixtures.
const assert=require('node:assert/strict');
let chromium;try{({chromium}=require('@playwright/test'))}catch{({chromium}=require('playwright'))}
const endpoint=process.env.BOOKING_URL||'http://64.119.31.106:8187';
(async()=>{
 const browser=await chromium.launch({headless:true,channel:process.env.BOOKING_BROWSER||undefined});
 try{for(const width of [320,390,430]){
  const page=await browser.newPage({viewport:{width,height:844}});
  await page.addInitScript(()=>{
   // Delay the automatic initial lookup to test that it cannot replace a manual pickup.
   Object.defineProperty(navigator,'geolocation',{value:{getCurrentPosition(ok,fail){
    if(!window.__initialLocation){window.__initialLocation=ok;return}
    if(window.__denyLocation){fail({code:1});return}
    ok({coords:{latitude:47.94,longitude:106.93}});
   }}});
   if(!crypto.randomUUID)crypto.randomUUID=()=> '12345678-1234-4234-8234-123456789012';
   window.google={maps:{
    Map:class{constructor(el){this.el=el}addListener(name,fn){this.el.addEventListener(name,()=>fn({latLng:{lat:()=>47.93,lng:()=>106.91}}))}fitBounds(){}panTo(){}},
    Marker:class{setMap(){}setPosition(){}},Polyline:class{setMap(){}},LatLngBounds:class{extend(){}},SymbolPath:{CIRCLE:0},
    Geocoder:class{async geocode({location}){return{results:[{formatted_address:`Газрын зураг ${location.lat}`}]} }}
   }};
  });
  const service={id:'porter',code:'porter',name_mn:'Портер',description_mn:'1 тонн хүртэл',icon:'truck',base_fare:30000,per_km_rate:2000,is_active:true,sort_order:2};
  const destination={lat:47.90,lng:106.92,address:'Хүргэх туршилтын хаяг'};
  const pickup={lat:47.92,lng:106.90,address:'Авах туршилтын хаяг'};
  const quotes=[];let failQuote=false,created=null;
  await page.route('**/api/**',async route=>{
   const req=route.request(),url=new URL(req.url()),p=url.pathname;let body={};
   if(p.endsWith('/auth/otp/request'))body={ok:true};
   else if(p.endsWith('/auth/otp/verify'))body={user:{name:'Туршилт'}};
   else if(p.endsWith('/auth/me'))body={name:'Туршилт'};
   else if(p.endsWith('/services'))body=[service];
   else if(p.endsWith('/places'))body=[{id:url.searchParams.get('q').includes('Авах')?'pickup':'destination',address:url.searchParams.get('q')}];
   else if(p.endsWith('/places/pickup'))body=pickup;
   else if(p.endsWith('/places/destination'))body=destination;
   else if(p.endsWith('/quotes')){
    const data=req.postDataJSON();quotes.push(data);
    if(failQuote)return route.fulfill({status:503,json:{detail:'UNKNOWN'}});
    body={distance_km:6,duration_minutes:15,loader_rate:25000,quote_token:'fixture',prices:[{service,breakdown:{total:42000+data.loaders*25000}}]};
   }else if(p.endsWith('/orders')){
    created=req.postDataJSON();body={...created,id:'fixture-order',service_name:'Портер',total_price:created.expected_total,status:'pending',can_cancel:false};
   }else throw Error('Unexpected API request '+p);
   await route.fulfill({json:body});
  });
  await page.routeWebSocket('**/ws/orders/**',()=>{});
  await page.goto(endpoint);
  await page.locator('#phone').fill('99000003');await page.locator('#accept-terms').check();
  await page.getByRole('button',{name:'Үргэлжлүүлэх',exact:true}).click();
  await page.locator('#otp').fill('00');await page.getByRole('button',{name:'Баталгаажуулах',exact:true}).click();
  await page.getByRole('button',{name:'Хаашаа ачих вэ?'}).click();
  const search=page.getByRole('combobox'),order=page.locator('.order-action > .btn-accent');
  async function choose(text){await search.fill(text);await page.getByRole('option').first().waitFor();await search.press('ArrowDown');await search.press('Enter');await page.waitForFunction(()=>!document.querySelector('.order-action > .btn-accent').disabled)}
  await choose('Хүргэх');assert.deepEqual(quotes.at(-1).dropoff,destination);
  await page.getByRole('button',{name:'Авах хаягийг өөрчлөх',exact:true}).click();
  await search.fill('Авах');assert.equal(await order.isDisabled(),true);
  assert.equal(await page.getByRole('button',{name:'Үнэ дахин тооцоолох',exact:true}).count(),0);
  await page.getByRole('option').first().waitFor();await search.press('ArrowDown');await search.press('Enter');
  await page.waitForFunction(()=>!document.querySelector('.order-action > .btn-accent').disabled);
  assert.deepEqual(quotes.at(-1).pickup,pickup);assert.deepEqual(quotes.at(-1).dropoff,destination);
  await page.evaluate(()=>window.__initialLocation({coords:{latitude:48,longitude:107}}));
  assert.match(await page.locator('.pickup-stop dd').innerText(),/Авах туршилтын хаяг/);
  // Map taps edit the active endpoint, preserving the other endpoint.
  await page.getByRole('application',{name:'Газрын зураг'}).click();
  await page.waitForFunction(()=>!document.querySelector('.order-action > .btn-accent').disabled);
  assert.equal(quotes.at(-1).pickup.lat,47.93);assert.deepEqual(quotes.at(-1).dropoff,destination);
  await page.evaluate(()=>window.__denyLocation=true);
  await page.getByRole('button',{name:'Одоогийн байршил ашиглах',exact:true}).click();
  await page.locator('.order-action .error').waitFor();assert.equal(await order.isDisabled(),true);
  await page.evaluate(()=>window.__denyLocation=false);
  await page.getByRole('button',{name:'Одоогийн байршил ашиглах',exact:true}).click();
  await page.waitForFunction(()=>!document.querySelector('.order-action > .btn-accent').disabled);
  assert.equal(quotes.at(-1).pickup.lat,47.94);
  failQuote=true;await page.getByRole('application',{name:'Газрын зураг'}).click();
  await page.locator('.order-action .error').waitFor();assert.equal(await order.isDisabled(),true);
  failQuote=false;await page.getByRole('button',{name:'Үнэ дахин тооцоолох',exact:true}).click();
  await page.waitForFunction(()=>!document.querySelector('.order-action > .btn-accent').disabled);
  await page.locator('.loader-option input').check();await page.waitForFunction(()=>!document.querySelector('.order-action > .btn-accent').disabled);
  assert.equal(quotes.at(-1).loaders,1);assert.equal(quotes.at(-1).pickup.lat,47.93);
  await page.getByRole('button',{name:'Хүргэх газар',exact:true}).click();await choose('Хүргэх');
  assert.equal(quotes.at(-1).pickup.lat,47.93);
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  await page.getByRole('button',{name:'Бэлэн мөнгө',exact:true}).click();await order.click();
  await page.getByText('Жолооч хайж байна…',{exact:true}).waitFor();
  assert.equal(created.pickup.lat,47.93);assert.deepEqual(created.dropoff,destination);assert.equal(created.loaders,1);assert.equal(created.payment_method,'cash');assert.equal(created.expected_total,67000);
  console.log(`PASS ${width}px: pickup search/map/current location, delayed GPS, preserved destination, requote failure/retry, loader, order payload`);
  await page.close();
 }}finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
