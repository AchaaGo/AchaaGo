// Run against a built web app. Authentication/logout and Maps are isolated fixtures.
const assert=require('node:assert/strict');
const path=require('node:path');
const output=process.env.THEME_SCREENSHOTS;
if(output)require('node:fs').mkdirSync(output,{recursive:true});
let chromium;try{({chromium}=require('@playwright/test'))}catch{({chromium}=require('playwright'))}
const url=process.env.BOOKING_URL||'http://64.119.31.106:8187';
(async()=>{
 const browser=await chromium.launch({headless:true,channel:process.env.BOOKING_BROWSER||undefined});
 try{for(const width of [320,390,430,800]){
  const context=await browser.newContext({viewport:{width,height:700},colorScheme:"dark",reducedMotion:width===390?'reduce':'no-preference'});
  const page=await context.newPage();let logoutCalls=0,failLogout=true;
  const user={phone:'+97699000003',...(width===430?{name:'Туршилтын хэрэглэгч'}:{})};
  await page.addInitScript(()=>{
   window.__mapPresses=0;window.__mapCreates=0;
   window.google={maps:{Map:class{constructor(el){window.__mapCreates++;el.addEventListener('pointerdown',()=>window.__mapPresses++)}addListener(){}fitBounds(){}panTo(){}setOptions(options){window.__mapTheme=options.styles[0]}},Marker:class{setMap(){}setPosition(){}},Polyline:class{setMap(){}},LatLngBounds:class{extend(){}},SymbolPath:{CIRCLE:0}}};
  });
  await page.route(url+'/api/**',async route=>{
   const p=new URL(route.request().url()).pathname;let body={};
   if(p.endsWith('/auth/otp/request'))body={ok:true};
   else if(p.endsWith('/auth/otp/verify'))body={user};
   else if(p.endsWith('/auth/me'))body=user;
   else if(p.endsWith('/services'))body=[{id:'porter',code:'porter',name_mn:'Портер',description_mn:'Ачаа',icon:'truck',base_fare:30000,per_km_rate:2000,is_active:true,sort_order:2}];
   else if(p.endsWith('/auth/logout')){assert.equal(route.request().method(),'POST');assert.deepEqual(route.request().postDataJSON(),{});logoutCalls++;if(failLogout)return route.fulfill({status:503,json:{detail:'UNKNOWN'}});body={ok:true};}
   else throw Error('Unexpected API request '+p);
   await route.fulfill({json:body});
  });
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(()=>{
   const observer=new MutationObserver(()=>{if(document.body){window.__firstTheme=document.documentElement.dataset.theme;observer.disconnect()}});
   observer.observe(document,{childList:true,subtree:true});
  });
  await page.goto(url);await page.getByRole('button',{name:'Гэгээтэй горимд шилжих',exact:true}).waitFor();
  assert.equal(await page.evaluate(()=>window.__firstTheme),'dark');
  assert.equal(await page.evaluate(()=>localStorage.getItem('achaago-theme')),null);
  const box=await page.locator('#phone').boundingBox();
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  if(output&&width===390)await page.screenshot({path:path.join(output,'dark-login.png'),fullPage:true});
  await page.emulateMedia({colorScheme:'light'});await page.waitForFunction(()=>document.documentElement.dataset.theme==='light');
  await page.emulateMedia({colorScheme:'dark'});await page.waitForFunction(()=>document.documentElement.dataset.theme==='dark');
  await page.locator('.theme-toggle').click();assert.equal(await page.evaluate(()=>localStorage.getItem('achaago-theme')),'light');
  assert.deepEqual(await page.locator('#phone').boundingBox(),box);
  await page.reload();await page.getByRole('button',{name:'Харанхуй горимд шилжих',exact:true}).waitFor();
  assert.equal(await page.evaluate(()=>window.__firstTheme),'light');
  if(output&&width===390)await page.screenshot({path:path.join(output,'light-login.png'),fullPage:true});
  await page.locator('.theme-toggle').focus();await page.keyboard.press('Enter');
  assert.equal(await page.evaluate(()=>localStorage.getItem('achaago-theme')),'dark');
  await page.reload();await page.getByRole('button',{name:'Гэгээтэй горимд шилжих',exact:true}).waitFor();
  assert.equal(await page.evaluate(()=>window.__firstTheme),'dark');
  const second=await context.newPage();await second.goto(url+'/terms');await second.getByRole('button',{name:'Гэгээтэй горимд шилжих',exact:true}).click();
  await page.waitForFunction(()=>document.documentElement.dataset.theme==='light');
  await second.locator('.theme-toggle').click();await page.waitForFunction(()=>document.documentElement.dataset.theme==='dark');await second.close();
  await page.locator('#phone').fill('99000003');assert(await page.getByRole('button',{name:'Үргэлжлүүлэх',exact:true}).isDisabled());await page.locator('#accept-terms').check();
  await page.getByRole('button',{name:'Үргэлжлүүлэх',exact:true}).click();await page.locator('#otp').fill('00');await page.getByRole('button',{name:'Баталгаажуулах',exact:true}).click();
  await page.getByRole('application',{name:'Газрын зураг'}).waitFor();
  const profile=await page.getByRole('button',{name:'Профайл',exact:true}).boundingBox(),toggle=await page.locator('.theme-toggle').boundingBox();
  assert(toggle.x+toggle.width<=profile.x||toggle.x>=profile.x+profile.width);
  const mapCreates=await page.evaluate(()=>window.__mapCreates);
  await page.locator('.theme-toggle').click();await page.waitForFunction(()=>window.__mapTheme);assert.equal(await page.evaluate(()=>window.__mapCreates),mapCreates);
  await page.locator('.theme-toggle').click();
  await page.getByRole('button',{name:'Цэс',exact:true}).click();await page.getByRole('dialog').waitFor();
  if(output&&width===390)await page.screenshot({path:path.join(output,'dark-menu.png'),fullPage:true});
  await page.keyboard.press('Escape');await page.locator('.home-search').click();
  await page.locator('.route-screen .map-stage .theme-toggle').waitFor();
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  if(output&&width===390)await page.screenshot({path:path.join(output,'dark-booking.png'),fullPage:true});
  assert.deepEqual(errors,[]);
  console.log(`PASS ${width}px: first paint, system preference, stored choice, reload, cross-tab, keyboard, unchanged input bounds, dark login/menu/booking, map instance preserved`);
  if(width===390){
    const reopened=await browser.newContext({storageState:await context.storageState(),colorScheme:'light'});
    const fresh=await reopened.newPage();await fresh.goto(url+'/terms');await fresh.getByRole('button',{name:'Гэгээтэй горимд шилжих',exact:true}).waitFor();await reopened.close();
    await page.emulateMedia({reducedMotion:'reduce'});await page.locator('.theme-toggle').click();
    assert.equal(await page.locator('.theme-toggle').evaluate(el=>getComputedStyle(el).transitionDuration),'0s');
  }
  await context.close();
 }
 const blocked=await browser.newContext({colorScheme:'dark'});const page=await blocked.newPage();
 await page.addInitScript(()=>{Object.defineProperty(Storage.prototype,'getItem',{value(){throw new Error('blocked')}});Object.defineProperty(Storage.prototype,'setItem',{value(){throw new Error('blocked')}})});
 await page.goto(url);await page.getByRole('button',{name:'Гэгээтэй горимд шилжих',exact:true}).click();
 assert.equal(await page.evaluate(()=>document.documentElement.dataset.theme),'light');
 await page.emulateMedia({colorScheme:'light'});await page.emulateMedia({colorScheme:'dark'});
 assert.equal(await page.evaluate(()=>document.documentElement.dataset.theme),'light');
 await blocked.close();console.log('PASS unavailable storage: usable toggle and system fallback');
 }finally{await browser.close()}
})().catch(error=>{console.error(error);process.exitCode=1});
