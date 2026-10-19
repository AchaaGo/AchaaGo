// All requests are intercepted; no live application, SMS, orders or provider calls.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {chromium,expect}=require('@playwright/test');
const root=path.resolve(__dirname,'../.next');
(async()=>{
 const browser=await chromium.launch({headless:true,channel:process.env.BOOKING_BROWSER||'chrome'});
 try{for(const width of [320,390,430]){
  const page=await browser.newPage({viewport:{width,height:844},isMobile:true,hasTouch:true,colorScheme:width===390?'dark':'light'});
  const errors=[];page.on('pageerror',error=>errors.push(error.message));
  await page.route('**/*',async route=>{
   const url=new URL(route.request().url());
   if(url.origin!=='http://achaago.test')return route.abort();
   if(url.pathname.startsWith('/api/')||url.pathname==='/address/what3words')return route.fallback();
   const rel=url.pathname.startsWith('/_next/static/')?url.pathname.replace('/_next/',''):url.pathname==='/'?'server/app/index.html':null;
   if(!rel)return route.fulfill({status:404,body:''});
   const file=path.resolve(root,rel);assert(file.startsWith(root+path.sep));
   await route.fulfill({body:fs.readFileSync(file),contentType:file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':file.endsWith('.woff2')?'font/woff2':'text/html'});
  });
  await page.addInitScript(()=>{
   window.__routes=[];
   Object.defineProperty(navigator,'geolocation',{value:{getCurrentPosition(){}}});
   window.google={maps:{
    Map:class{setOptions(){}addListener(){}fitBounds(){}panTo(){}},Marker:class{setMap(){}setPosition(){}},Polyline:class{setMap(){}addListener(){}},LatLngBounds:class{extend(){}},SymbolPath:{CIRCLE:0},event:{clearInstanceListeners(){}},
    importLibrary:async()=>({Route:{computeRoutes:async request=>{window.__routes.push(request);return {routes:[{path:[request.origin,request.destination],durationMillis:600000,staticDurationMillis:500000,distanceMeters:5000}]}}}})
   }};
  });
  const service={id:'porter',code:'porter',name_mn:'Портер',description_mn:'1 тонн хүртэл',icon:'truck',base_fare:30000,per_km_rate:2000};
  const googleDestination={lat:47.90,lng:106.92,address:'Хүргэх туршилтын хаяг'};
  const googlePickup={lat:47.92,lng:106.90,address:'Авах туршилтын хаяг'};
  const wordPickup={lat:47.9186123,lng:106.9177123,address:'///гурван.үг.хаяг'};
  const wordDestination={lat:47.9211123,lng:106.9511123,address:'///filled.count.soap'};
  const quotes=[],wordRequests=[];let failure=false,slow=false;
  await page.route('**/api/**',async route=>{
   const req=route.request(),url=new URL(req.url()),p=url.pathname;let body;
   if(p.endsWith('/auth/me'))body={id:'fixture-user',phone:'+97699000003'};
   else if(p.endsWith('/config'))body={dev_otp:true};
   else if(p.endsWith('/orders'))body=[];
   else if(p.endsWith('/services'))body=[service];
   else if(p.endsWith('/places'))body=[{id:url.searchParams.get('q').includes('Авах')?'pickup':'destination',address:url.searchParams.get('q')}];
   else if(p.endsWith('/places/pickup'))body=googlePickup;
   else if(p.endsWith('/places/destination'))body=googleDestination;
   else if(p.endsWith('/quotes')){quotes.push(req.postDataJSON());body={distance_km:6,duration_minutes:15,loader_rate:25000,quote_token:'fixture',prices:[{service,breakdown:{total:42000}}]};}
   else throw Error('Unexpected API request '+p);
   await route.fulfill({json:body});
  });
  await page.route('**/address/what3words',async route=>{
   const body=route.request().postDataJSON();wordRequests.push(body);
   if(slow)await new Promise(resolve=>setTimeout(resolve,600));
   if(failure)return route.fulfill({status:404,json:{detail:'W3W_NOT_FOUND'}});
   const point=body.words.startsWith('гурван')?wordPickup:wordDestination;
   await route.fulfill({json:body.action==='suggest'?{suggestions:[{words:point.address.slice(3),nearestPlace:'Улаанбаатар',country:'MN'}]}:{point}}).catch(()=>{});
  });
  await page.goto('http://achaago.test');await page.getByRole('button',{name:'Хаашаа ачих вэ?'}).click();
  const methods=page.getByRole('group',{name:'Хаяг оруулах арга'}),targets=page.locator('.address-targets');
  const google=methods.getByRole('button',{name:'Google Maps',exact:true}),words=methods.getByRole('button',{name:'/// what3words',exact:true});
  await expect(google).toHaveAttribute('aria-pressed','true');
  await page.locator('#destination').fill('Хүргэх');await page.getByRole('option').first().click();
  await expect(page.locator('.order-action > .btn-accent')).toBeEnabled();assert.equal(quotes.length,1);
  await targets.getByRole('button',{name:'Авах газар',exact:true}).click();await expect(google).toHaveAttribute('aria-pressed','true');
  await words.click();assert.equal(quotes.length,1);
  const input=page.locator('#w3w-address');
  await input.fill('two.words');await page.getByRole('button',{name:'Сонгох',exact:true}).click();
  await expect(page.locator('#w3w-feedback')).toContainText('what3words хаяг буруу');assert.equal(wordRequests.length,0);
  await input.fill('///гурван.үг.хаяг');await page.getByRole('option').first().waitFor();
  await input.press('ArrowUp');await expect(page.getByRole('option').first()).toHaveAttribute('aria-selected','true');
  await input.press('ArrowDown');await input.press('Enter');
  await expect(page.locator('.order-action > .btn-accent')).toBeEnabled();
  await expect(page.locator('.pickup-stop dd')).toContainText(wordPickup.address);
  assert.deepEqual(quotes.at(-1).pickup,wordPickup);assert.deepEqual(quotes.at(-1).dropoff,googleDestination);
  await page.waitForFunction(()=>window.__routes.at(-1)?.origin.lat===47.9186123);
  await targets.getByRole('button',{name:'Хүргэх газар',exact:true}).click();await expect(google).toHaveAttribute('aria-pressed','true');
  await words.click();failure=true;await input.fill('filled.count.soap');await page.getByRole('button',{name:'Сонгох',exact:true}).click();
  await expect(page.locator('#w3w-feedback')).toContainText('what3words хаяг олдсонгүй');
  assert.deepEqual(quotes.at(-1).dropoff,googleDestination);
  await page.getByRole('button',{name:'Google Maps хаяг ашиглах',exact:true}).click();await expect(google).toHaveAttribute('aria-pressed','true');
  // A resolving request must not apply to the other endpoint after switching editors.
  failure=false;slow=true;await words.click();await page.getByRole('button',{name:'Сонгох',exact:true}).click();
  await targets.getByRole('button',{name:'Авах газар',exact:true}).click();
  await page.waitForTimeout(750);assert.deepEqual(quotes.at(-1).dropoff,googleDestination);assert.deepEqual(quotes.at(-1).pickup,wordPickup);
  await expect(words).toHaveAttribute('aria-pressed','true');slow=false;
  await targets.getByRole('button',{name:'Хүргэх газар',exact:true}).click();await page.getByRole('button',{name:'Сонгох',exact:true}).click();
  await expect(page.locator('.destination-stop dd')).toContainText(wordDestination.address);
  assert.deepEqual(quotes.at(-1).pickup,wordPickup);assert.deepEqual(quotes.at(-1).dropoff,wordDestination);
  await targets.getByRole('button',{name:'Авах газар',exact:true}).click();await google.click();
  const count=quotes.length;await page.locator('#destination').fill('Авах');await page.getByRole('option').first().click();
  await expect(page.locator('.order-action > .btn-accent')).toBeEnabled();assert.equal(quotes.length,count+1);
  assert.deepEqual(quotes.at(-1).pickup,googlePickup);assert.deepEqual(quotes.at(-1).dropoff,wordDestination);
  const handle=page.locator('.map-sheet-handle');await handle.click();await expect(page.locator('.map-sheet')).toHaveAttribute('data-collapsed','true');await handle.click();
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));assert.deepEqual(errors,[]);
  console.log(`PASS ${width}px: default Google, independent methods, Unicode/keyboard suggestions, exact coordinates, mixed quotes/routes, failures, stale response, sheet/theme`);
  await page.close();
 }}finally{await browser.close()}
})().catch(error=>{console.error(error);process.exitCode=1});
