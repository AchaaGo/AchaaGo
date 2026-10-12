// Isolated browser regression: all API, Maps SDK and location responses are fixtures.
const assert=require('node:assert/strict');
let chromium;try{({chromium}=require('@playwright/test'))}catch{({chromium}=require('playwright'))}
const endpoint=process.env.BOOKING_URL||'http://64.119.31.106:8187';
(async()=>{
 const browser=await chromium.launch({headless:true,channel:process.env.BOOKING_BROWSER||undefined});
 try{for(const width of [320,390,430]){
  const page=await browser.newPage({viewport:{width,height:844},hasTouch:true,isMobile:true,colorScheme:width===390?'dark':'light'});
  await page.addInitScript(()=>{
   // Delay the automatic initial lookup to test that it cannot replace a manual pickup.
   Object.defineProperty(navigator,'geolocation',{value:{getCurrentPosition(ok,fail){
    if(!window.__initialLocation){window.__initialLocation=ok;return}
    if(window.__denyLocation){fail({code:1});return}
    ok({coords:{latitude:47.94,longitude:106.93}});
   }}});
   if(!crypto.randomUUID)crypto.randomUUID=()=> '12345678-1234-4234-8234-123456789012';
   window.google={maps:{
    Map:class{constructor(el){this.el=el;window.__maps=(window.__maps||0)+1}setOptions(){}addListener(name,fn){this.el.addEventListener(name,()=>fn({latLng:{lat:()=>47.93,lng:()=>106.91}}))}fitBounds(){}panTo(){}},
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
  const errors=[];page.on('pageerror',e=>errors.push(e.message));await page.goto(endpoint);
  await page.locator('#phone').fill('99000003');await page.locator('#accept-terms').check();
  await page.getByRole('button',{name:'Үргэлжлүүлэх',exact:true}).click();
  await page.locator('#otp').fill('00');await page.getByRole('button',{name:'Баталгаажуулах',exact:true}).click();

  await page.locator('.map-sheet-handle').waitFor();
  const handle=page.locator('.map-sheet-handle'),sheet=page.locator('.map-sheet'),content=page.locator('.map-sheet-content');
  const cdp=await page.context().newCDPSession(page);
  async function swipe(x,y,dy){
    await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x,y}]});
    for(let i=1;i<=12;i++){await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x,y:y+dy*i/12}]});await page.waitForTimeout(16)}
    await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
  }
  async function expectCollapsed(value){await page.waitForFunction(value=>document.querySelector('.map-sheet').dataset.collapsed===String(value),value);await page.waitForTimeout(250)}
  const mapCount=await page.evaluate(()=>window.__maps);
  let h=await handle.boundingBox();await swipe(h.x+h.width/2,h.y+25,200);await expectCollapsed(true);
  let minimized=await sheet.boundingBox();assert(minimized.y>750);assert.equal(await content.getAttribute('inert'),'');
  assert.equal(await page.evaluate(()=>scrollY),0);assert.equal(await page.evaluate(()=>window.__maps),mapCount);
  if(process.env.SHEET_SCREENSHOTS&&width===390)await page.screenshot({path:process.env.SHEET_SCREENSHOTS+'/sheet-minimized.png'});
  await handle.click();await expectCollapsed(false);
  await handle.focus();await page.keyboard.press('ArrowDown');await expectCollapsed(true);
  await page.keyboard.press('ArrowUp');await expectCollapsed(false);
  h=await handle.boundingBox();await swipe(h.x+h.width/2,h.y+25,160);await expectCollapsed(true);
  h=await handle.boundingBox();await swipe(h.x+h.width/2,h.y+25,-200);await expectCollapsed(false);
  await page.getByRole('button',{name:'Хаашаа ачих вэ?'}).click();
  const search=page.getByRole('combobox'),order=page.locator('.order-action > .btn-accent');
  await search.fill('Хүргэх');await page.getByRole('option').first().waitFor();await search.press('ArrowDown');await search.press('Enter');
  await page.waitForFunction(()=>!document.querySelector('.order-action > .btn-accent').disabled);
  // Downward pull on noninteractive content collapses only when scrolled to the top.
  await content.evaluate(el=>el.scrollTop=0);
  let c=await content.boundingBox();await swipe(c.x+c.width-18,c.y+18,100);await expectCollapsed(true);
  await handle.click();await expectCollapsed(false);
  assert.equal(await order.isEnabled(),true);assert.deepEqual(quotes.at(-1).dropoff,destination);
  // Upward swipes scroll the form without collapsing it.
  c=await content.boundingBox();await swipe(c.x+c.width-8,c.y+c.height-45,-130);
  assert((await content.evaluate(el=>el.scrollTop))>0);assert.equal(await sheet.getAttribute('data-collapsed'),'false');
  await page.locator('.loader-option input').check();await page.waitForFunction(()=>!document.querySelector('.order-action > .btn-accent').disabled);
  assert.equal(quotes.at(-1).loaders,1);
  await page.getByRole('button',{name:'Бэлэн мөнгө',exact:true}).click();
  h=await handle.boundingBox();await swipe(h.x+h.width/2,h.y+25,100);await expectCollapsed(true);
  await handle.click();await expectCollapsed(false);
  assert(await page.locator('.loader-option input').isChecked());assert.equal(await page.getByRole('button',{name:'Бэлэн мөнгө',exact:true}).getAttribute('aria-pressed'),'true');
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  if(process.env.SHEET_SCREENSHOTS&&width===390){await content.evaluate(el=>el.scrollTop=0);await page.screenshot({path:process.env.SHEET_SCREENSHOTS+'/sheet-expanded.png'})}
  await page.emulateMedia({reducedMotion:'reduce'});assert.equal(await sheet.evaluate(el=>getComputedStyle(el).transitionDuration),'0s');
  await order.click();await page.getByText('Жолооч хайж байна…',{exact:true}).waitFor();
  await handle.click();await expectCollapsed(true);await handle.click();await expectCollapsed(false);
  assert.equal(created.payment_method,'cash');assert.equal(created.loaders,1);
  await page.setViewportSize({width:800,height:844});assert.equal(await handle.isVisible(),false);assert.equal(await content.getAttribute('inert'),null);
  assert.deepEqual(errors,[]);
  console.log(`PASS ${width}px: touch drag both ways, tap/keyboard, content scroll/pull, full map, unchanged map instance, preserved quote/loader/payment, order, reduced motion, desktop`);
  await page.close();
 }}finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
