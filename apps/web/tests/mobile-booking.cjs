// Run against a built web app: BOOKING_URL=http://host:8187 node tests/mobile-booking.cjs
// All API responses are isolated fixtures. No customer orders or SMS are sent.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
let chromium;
try { ({chromium} = require('@playwright/test')); }
catch { ({chromium} = require('playwright')); }

const url = process.env.BOOKING_URL || 'http://64.119.31.106:8187';
const output = process.env.BOOKING_SCREENSHOTS;
const services = [
  {id:'m',code:'motorcycle',name_mn:'Мотоцикл',description_mn:'Жижиг хүргэлт',icon:'package',sort_order:0},
  {id:'a',code:'amjirgaa',name_mn:'Амжиргаа',description_mn:'Бага, дунд ачаа',icon:'package',sort_order:1},
  {id:'p',code:'porter',name_mn:'Портер',description_mn:'1 тонн хүртэл',icon:'truck',sort_order:2},
].map(s=>({...s,is_active:true,base_fare:999,per_km_rate:999}));
const totals=[17500,32500,46500]; // Fixtures only; not motorcycle launch pricing.
const destination={lat:47.91,lng:106.92,address:'Улаанбаатар, Сүхбаатар дүүрэг, Энхтайваны өргөн чөлөө, 15-р байр'};

(async()=>{
  const browser=await chromium.launch({headless:true,channel:process.env.BOOKING_BROWSER||undefined});
  try {
    for(const width of [320,360,390,430,800]) {
      const context=await browser.newContext({viewport:{width,height:844},locale:'mn-MN'});
      const page=await context.newPage();
      let failQuote=false,orderCalls=0;
      await page.route('**/api/**',async route=>{
        const request=route.request(),p=new URL(request.url()).pathname;
        let body={};
        if(p.endsWith('/auth/otp/request')) body={ok:true};
        else if(p.endsWith('/auth/otp/verify')) body={user:{name:'Туршилт'}};
        else if(p.endsWith('/auth/me')) body={name:'Туршилт'};
        else if(p.endsWith('/services')) body=services;
        else if(p.endsWith('/places')) body=[{id:'destination',address:destination.address}];
        else if(p.includes('/places/')) body=destination;
        else if(p.endsWith('/quotes')) {
          if(failQuote) return route.fulfill({status:503,json:{detail:'UNKNOWN'}});
          const loaders=request.postDataJSON().loaders;
          body={distance_km:7.5,duration_minutes:19,loader_rate:25000,approximate:false,quote_token:'fixture-token',prices:services.map((service,i)=>({service,breakdown:{total:totals[i]+loaders*25000}}))};
        } else if(p.endsWith('/orders')) {orderCalls++;throw Error('Unexpected real-order attempt');}
        else if(p.endsWith('/config')) body={};
        else throw Error('Unhandled API request '+p);
        await route.fulfill({json:body});
      });
      // Exercise the existing API fallback and keyboard selection deterministically.
      await page.route('**/maps.googleapis.com/**',route=>route.abort());
      await page.goto(url);
      await page.getByRole('textbox',{name:'Утасны дугаар',exact:true}).fill('99000003');
      await page.getByRole('checkbox').check();
      await page.getByRole('button',{name:'Үргэлжлүүлэх',exact:true}).click();
      await page.locator('input[autocomplete="one-time-code"]').fill('00');
      await page.getByRole('button',{name:'Баталгаажуулах',exact:true}).click();
      await page.getByRole('button',{name:'Хаашаа ачих вэ?'}).click();
      const cards=page.locator('.mobile-vehicle-selector .vehicle-card');
      if(width<768) {
        await cards.first().waitFor({state:'visible'});
        assert.equal(await cards.count(),3);
        assert.match(await cards.first().innerText(),/Хаяг сонгоход үнэ гарна/);
        assert(!(await cards.first().innerText()).includes('999'));
      } else assert.equal(await cards.first().isVisible(),false);
      await page.getByRole('combobox').fill('Сүхбаатар');
      await page.getByRole('option').first().waitFor();
      await page.getByRole('combobox').press('ArrowDown');
      await page.getByRole('combobox').press('Enter');
      const orderButton=page.locator('.order-action > button.btn-accent');
      await orderButton.waitFor();
      await page.waitForFunction(()=>!document.querySelector('.order-action > button.btn-accent').disabled);
      if(width<768) {
        for(let i=0;i<3;i++) assert.match(await cards.nth(i).innerText(),new RegExp(totals[i].toLocaleString('mn-MN')));
        await cards.first().click();
        assert.equal(await cards.first().getAttribute('aria-pressed'),'true');
        assert.equal(await cards.first().locator('.vehicle-check svg').count(),1);
        assert.match(await orderButton.innerText(),/Мотоцикл/);
        await page.getByRole('button',{name:'Бэлэн мөнгө',exact:true}).click();
        assert.equal(await page.getByRole('button',{name:'Бэлэн мөнгө',exact:true}).getAttribute('aria-pressed'),'true');
        await page.getByRole('button',{name:'QPay',exact:true}).click();
        await page.locator('.loader-option input').check();
        await page.waitForFunction(()=>!document.querySelector('.order-action > button.btn-accent').disabled);
        assert.match(await cards.first().innerText(),/42,500/);
        await page.locator('.loader-option input').uncheck();
        await page.waitForFunction(()=>!document.querySelector('.order-action > button.btn-accent').disabled);
        const overflow=await page.evaluate(()=>({width:innerWidth,scroll:document.documentElement.scrollWidth,bad:[...document.querySelectorAll('.vehicle-card,.booking-addresses,.booking-stop dd,.payment-options,.order-action')].filter(e=>e.getBoundingClientRect().width&&e.scrollWidth>e.clientWidth+1).map(e=>e.className)}));
        assert(overflow.scroll<=overflow.width,JSON.stringify(overflow));
        assert.deepEqual(overflow.bad,[],JSON.stringify(overflow));
        const heights=await cards.evaluateAll(nodes=>nodes.map(n=>n.getBoundingClientRect().height));
        assert(heights.every(height=>height>=44));
        if(output&&[320,390,430].includes(width)) {
          fs.mkdirSync(output,{recursive:true});
          await page.evaluate(()=>window.scrollTo(0,0));
          await page.screenshot({fullPage:true,path:path.join(output,`mobile-vehicles-${width}-test-preview.png`)});
        }
        failQuote=true;
        await page.locator('.loader-option input').check();
        await page.locator('.order-action .error[role="alert"]').waitFor();
        assert.equal(await orderButton.isDisabled(),true);
        await page.getByRole('button',{name:'Үнэ дахин тооцоолох',exact:true}).waitFor();
        failQuote=false;
        await page.getByRole('button',{name:'Үнэ дахин тооцоолох',exact:true}).click();
        await page.waitForFunction(()=>!document.querySelector('.order-action > button.btn-accent').disabled);
      }
      assert.equal(orderCalls,0);
      console.log(`PASS ${width}px: layout, quote prices, keyboard search${width<768?', selection, loader, payment, quote-error recovery':''}`);
      await context.close();
    }
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1});
