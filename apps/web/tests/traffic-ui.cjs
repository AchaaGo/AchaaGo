// Offline browser test of the production build. Never contacts a live app/API/Google.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {chromium}=require('@playwright/test');
const root=path.resolve(__dirname,'../.next');
(async()=>{
 const browser=await chromium.launch({headless:true,channel:process.env.BOOKING_BROWSER||'chrome'});
 try{for(const [width,mode] of [[320,'traffic'],[390,'traffic'],[430,'single'],[390,'fallback'],[390,'error']]){
  const page=await browser.newPage({viewport:{width,height:844},isMobile:true,hasTouch:true,colorScheme:width===390?'dark':'light'});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.route('**/*',async route=>{
   const url=new URL(route.request().url());
   if(url.origin!=='http://achaago.test')return route.abort();
   if(url.pathname.startsWith('/api/'))return route.fallback();
   const rel=url.pathname.startsWith('/_next/static/')?url.pathname.replace('/_next/',''):url.pathname==='/'?'server/app/index.html':null;
   if(!rel)return route.fulfill({status:404,body:''});
   const file=path.resolve(root,rel);assert(file.startsWith(root+path.sep));
   await route.fulfill({body:fs.readFileSync(file),contentType:file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':file.endsWith('.woff2')?'font/woff2':'text/html'});
  });
  await page.addInitScript(mode=>{
   window.__requests=[];window.__lines=[];
   Object.defineProperty(navigator,'geolocation',{value:{getCurrentPosition(){}}});
   window.google={maps:{
    Map:class{constructor(){window.__maps=(window.__maps||0)+1}setOptions(){}addListener(){}fitBounds(){}panTo(){}},
    Marker:class{setMap(){}setPosition(){}},
    Polyline:class{constructor(options){this.options=options;window.__lines.push(this)}setMap(map){this.options.map=map}addListener(name,fn){this[name]=fn}},
    LatLngBounds:class{extend(){}},SymbolPath:{CIRCLE:0},event:{clearInstanceListeners(){}},
    importLibrary:async()=>({Route:{computeRoutes:async request=>{
     window.__requests.push(request);
     await new Promise(resolve=>setTimeout(resolve,200));
     if(mode==='error'||(mode==='fallback'&&request.routingPreference==='TRAFFIC_AWARE_OPTIMAL'))throw Error('Fixture unavailable');
     const make=(duration,distance)=>({path:[request.origin,{lat:47.91,lng:106.94},request.destination],durationMillis:duration*60000,staticDurationMillis:19*60000,distanceMeters:distance,
      speedPaths:[{path:[request.origin,{lat:47.91,lng:106.94}],speed:'SLOW'}]});
     return {routes:mode==='single'?[make(27,13800)]:[make(32,12100),make(27,13800)]};
    }}})
   }};
  },mode);
  const service={id:'porter',code:'porter',name_mn:'Портер',description_mn:'1 тонн хүртэл',icon:'truck',base_fare:30000,per_km_rate:2000};
  const destination={lat:47.90,lng:106.92,address:'Хүргэх туршилтын хаяг'};
  let signedIn=false;
  await page.route('**/api/**',async route=>{
   const url=new URL(route.request().url()),p=url.pathname;let body;
   if(p.endsWith('/auth/otp/request'))body={ok:true};
   else if(p.endsWith('/auth/otp/verify')){signedIn=true;body={user:{phone:'+97699000003'}};}
   else if(p.endsWith('/auth/me')){if(!signedIn)return route.fulfill({status:401,json:{detail:'LOGIN_REQUIRED'}});body={phone:'+97699000003'};}
   else if(p.endsWith('/auth/refresh'))return route.fulfill({status:401,json:{detail:'SESSION_EXPIRED'}});
   else if(p.endsWith('/config'))body={dev_otp:true};
   else if(p.endsWith('/orders'))body=[];
   else if(p.endsWith('/services'))body=[service];
   else if(p.endsWith('/places'))body=[{id:'destination',address:'Хүргэх туршилтын хаяг'}];
   else if(p.endsWith('/places/destination'))body=destination;
   else if(p.endsWith('/quotes'))body={distance_km:6,duration_minutes:15,loader_rate:25000,quote_token:'fixture',prices:[{service,breakdown:{total:42000}}]};
   else throw Error('Unexpected request '+p);
   await route.fulfill({json:body});
  });
  await page.goto('http://achaago.test');
  await page.locator('#phone').fill('99000003');await page.locator('#accept-terms').check();
  await page.getByRole('button',{name:'Үргэлжлүүлэх',exact:true}).click();
  await page.locator('#otp').fill('00');
  await page.getByRole('button',{name:'Хаашаа ачих вэ?'}).click();
  const search=page.getByRole('combobox');
  await search.fill('Хүргэх');await page.getByRole('option').first().waitFor();
  assert.equal(await page.evaluate(()=>window.__requests.length),0,'typing must not route');
  await search.press('ArrowDown');await search.press('Enter');
  await page.getByText('Замын нөхцөл тооцоолж байна…',{exact:true}).waitFor();
  const summary=page.locator('.traffic-summary');
  if(mode==='error'){
   await summary.getByText('Авто замын маршрут олдсонгүй. Дахин оролдоно уу.').waitFor();
   assert(await page.locator('.order-action > .btn-accent').isEnabled());
   await summary.getByRole('button').click();await page.waitForTimeout(250);
   assert.equal(await page.evaluate(()=>window.__requests.length),2,'failure cooldown');
  }else{
   await summary.getByText('27 мин · 13.8 км',{exact:true}).first().waitFor();
   if(mode==='fallback')await summary.getByText('Одоогийн замын хөдөлгөөний мэдээлэл авах боломжгүй байна.').waitFor();
   else await summary.getByText('Түгжрэлийн саатал: +8 мин').waitFor();
   const options=summary.locator('button[aria-pressed]');
   if(mode==='single')assert.equal(await options.count(),0);
   else{
    await options.nth(1).focus();await page.keyboard.press('Enter');
    assert.equal(await options.nth(1).getAttribute('aria-pressed'),'true');
    if(mode!=='fallback')await summary.getByText('Түгжрэлийн саатал: +13 мин').waitFor();
    await page.evaluate(()=>{const line=window.__lines.filter(line=>line.options.map&&line.options.strokeWeight===3).at(-1);line.click({stop(){}})});
    await page.waitForFunction(()=>document.querySelector('.traffic-options button')?.getAttribute('aria-pressed')==='true');
    assert.equal(await options.first().getAttribute('aria-pressed'),'true');
   }
   const count=await page.evaluate(()=>window.__requests.length);
   await page.locator('.loader-option input').check();await page.waitForTimeout(100);
   await page.getByRole('button',{name:'Бэлэн мөнгө',exact:true}).click();
   assert.equal(await page.evaluate(()=>window.__requests.length),count);
   await search.fill('Хүргэх дахин');await page.getByRole('option').first().waitFor();await search.press('ArrowDown');await search.press('Enter');
   await summary.getByText('27 мин · 13.8 км',{exact:true}).first().waitFor();
   assert.equal(await page.evaluate(()=>window.__requests.length),count,'same endpoints use cache');
  }
  const handle=page.locator('.map-sheet-handle');await handle.click();
  await page.waitForFunction(()=>document.querySelector('.map-sheet').dataset.collapsed==='true');
  await handle.click();assert.equal(await page.locator('.loader-option input').isChecked(),mode!=='error');
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  assert.deepEqual(errors,[]);
  if(mode==='traffic'&&width===390){
   await page.reload();await page.getByRole('button',{name:'Хаашаа ачих вэ?'}).waitFor();
   assert.equal(await page.evaluate(()=>window.__requests.length),0,'refresh without selected destination does not route');
  }
  console.log(`PASS ${width}px ${mode}: isolated production UI, keyboard/map route selection, cache, sheet, layout/theme`);
  await page.close();
 }}finally{await browser.close()}
})().catch(error=>{console.error(error);process.exitCode=1});
