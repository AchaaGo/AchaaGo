// Run against a built web app. Authentication/logout and Maps are isolated fixtures.
const assert=require('node:assert/strict');
let chromium;try{({chromium}=require('@playwright/test'))}catch{({chromium}=require('playwright'))}
const url=process.env.BOOKING_URL||'http://64.119.31.106:8187';
(async()=>{
 const browser=await chromium.launch({headless:true,channel:process.env.BOOKING_BROWSER||undefined});
 try{for(const width of [320,390,430]){
  const context=await browser.newContext({viewport:{width,height:700},reducedMotion:width===390?'reduce':'no-preference'});
  const page=await context.newPage();let logoutCalls=0,failLogout=true;
  const user={phone:'+97699000003',...(width===430?{name:'Туршилтын хэрэглэгч'}:{})};
  await page.addInitScript(()=>{
   window.__mapPresses=0;window.__mapCreates=0;
   window.google={maps:{Map:class{constructor(el){window.__mapCreates++;el.addEventListener('pointerdown',()=>window.__mapPresses++)}addListener(){}fitBounds(){}panTo(){}},Marker:class{setMap(){}setPosition(){}},Polyline:class{setMap(){}},LatLngBounds:class{extend(){}},SymbolPath:{CIRCLE:0}}};
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
  await page.goto(url);
  await page.locator('#phone').fill('99000003');await page.locator('#accept-terms').check();
  await page.getByRole('button',{name:'Үргэлжлүүлэх',exact:true}).click();await page.locator('#otp').fill('00');await page.getByRole('button',{name:'Баталгаажуулах',exact:true}).click();
  const menu=page.getByRole('button',{name:'Цэс',exact:true}),profile=page.getByRole('button',{name:'Профайл',exact:true});
  await menu.waitFor();await page.getByRole('application',{name:'Газрын зураг'}).waitFor();
  const before=await menu.boundingBox();
  await menu.click();const dialog=page.getByRole('dialog',{name:'Цэс',exact:true});await dialog.waitFor();
  assert.equal(await page.evaluate(()=>document.body.style.overflow),'hidden');
  assert.equal(await dialog.locator('button:disabled').count(),4);
  for(const label of ['Миний захиалгууд','Хадгалсан хаягууд','Тусламж','Жолооч болох'])assert.equal(await dialog.getByRole('button',{name:new RegExp(label)}).isDisabled(),true);
  assert.equal(await dialog.locator('.customer-order-dot').count(),0);
  for(let i=0;i<8;i++){await page.keyboard.press('Tab');assert.equal(await page.evaluate(()=>!!document.activeElement.closest('.map-toolbar,.home-search')),false);}
  const rows=await dialog.locator('.customer-panel-row').evaluateAll(nodes=>nodes.map(n=>n.getBoundingClientRect().height));assert(rows.every(h=>h>=48));
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  if(width===390)assert.equal(await dialog.evaluate(e=>getComputedStyle(e).animationName),'none');
  const popupPromise=context.waitForEvent('page');await dialog.getByRole('link',{name:/Үйлчилгээний нөхцөл/}).click();const popup=await popupPromise;await popup.waitForURL('**/terms');await popup.close();
  await page.keyboard.press('Escape');await dialog.waitFor({state:'detached'});
  assert.equal(await menu.evaluate(e=>document.activeElement===e),true);
  assert.equal(await page.evaluate(()=>document.body.style.overflow),'');assert.deepEqual(await menu.boundingBox(),before);
  await menu.click();await dialog.waitFor();await page.mouse.click(width/2,10);await dialog.waitFor({state:'detached'});
  assert.equal(await page.evaluate(()=>window.__mapPresses),0);
  await page.getByRole('application',{name:'Газрын зураг'}).click();assert.equal(await page.evaluate(()=>window.__mapPresses),1);assert.equal(await page.evaluate(()=>window.__mapCreates),1);
  await profile.click();const personal=page.getByRole('dialog',{name:'Профайл',exact:true});await personal.waitFor();
  assert.equal(await personal.locator('.customer-panel-identity strong').innerText(),user.name||'+976 9900 0003');
  assert.match(await personal.locator('.customer-panel-identity').innerText(),/\+976 9900 0003/);
  assert.equal(await personal.locator('button:disabled').count(),3);
  await personal.getByRole('button',{name:'Хаах',exact:true}).click();assert.equal(await profile.evaluate(e=>document.activeElement===e),true);
  await profile.click();await personal.getByRole('button',{name:'Гарах',exact:true}).click();await personal.getByRole('alert').waitFor();assert.equal(logoutCalls,1);
  assert.equal(await personal.getByRole('button',{name:'Гарах',exact:true}).isEnabled(),true);
  failLogout=false;await personal.getByRole('button',{name:'Гарах',exact:true}).click();await page.locator('#phone').waitFor();assert.equal(logoutCalls,2);
  console.log(`PASS ${width}px: menu/profile, disabled rows, terms, identity, focus, Escape/backdrop/close, scroll restoration, map gestures, logout failure/success${width===390?', reduced motion':''}`);
  await context.close();
 }}finally{await browser.close()}
})().catch(error=>{console.error(error);process.exitCode=1});
