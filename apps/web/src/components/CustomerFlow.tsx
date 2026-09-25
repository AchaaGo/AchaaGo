'use client';
import {useEffect,useRef,useState,type KeyboardEvent} from 'react';
import {ArrowLeft,Check,ChevronRight,MapPin,Menu,MessageSquare,Package,Phone,Search,Star,Truck,UserRound,X} from 'lucide-react';
import {api,ApiError,money,Order,Point,Quote,Service,uuid} from '@/lib/api';
import {createSessionToken,createStaleGuard,cycleHighlight,getGooglePlaceDetails,isGooglePlacesAvailable,reverseGeocode,searchGooglePlaces} from '@/lib/googlePlaces';
import {mn} from '@/lib/messages';
import {GoogleMapView} from './GoogleMapView';
import {PhoneLogin} from './PhoneLogin';
import {QpayDialog} from './QpayDialog';
import {CustomerPanel} from './CustomerPanel';
import {VehicleCards} from './VehicleCards';
import {customerCopy as copy} from './customerCopy';

type PlaceRow = {id:string; address:string; source:'google'|'demo'; place?:unknown};

type Screen='loading'|'login'|'home'|'route'|'finding'|'tracking'|'complete';
const fallback:Point={lat:47.9186,lng:106.9177,address:'Одоогийн байршил'};

function customerError(error:unknown) { return error instanceof ApiError ? error.message : copy.error; }

function ServiceIcon({type,size=25}:{type:string;size?:number}) { return type==='package'?<Package size={size}/>:<Truck size={size}/> }
function Summary({order}:{order:Order}) {
  return <div className="order-summary">
    <div className="summary-address"><MapPin size={18} aria-hidden="true"/><div><small>Авах хаяг</small>{order.pickup.address}</div></div>
    <div className="summary-address"><MapPin size={18} fill="var(--accent)" aria-hidden="true"/><div><small>Хүргэх хаяг</small>{order.dropoff.address}</div></div>
    <div className="summary-total"><span className="muted">{order.service_name}{order.loaders?' + ачигч':''} · {order.payment_method==='qpay'?'QPay':'Бэлэн мөнгө'}</span>{order.total_price!=null&&<strong>{money(order.total_price)}</strong>}</div>
  </div>;
}

export function CustomerFlow() {
  const [screen,setScreen]=useState<Screen>('loading'), [services,setServices]=useState<Service[]>([]), [selected,setSelected]=useState('');
  const [pickup,setPickup]=useState<Point>(fallback), [dropoff,setDropoff]=useState<Point|null>(null), [search,setSearch]=useState('');
  const [addressTarget,setAddressTarget]=useState<'pickup'|'dropoff'>('dropoff');
  const [pickupReady,setPickupReady]=useState(true);
  const pickupTouched=useRef(false);
  const [places,setPlaces]=useState<PlaceRow[]>([]), [placesLoading,setPlacesLoading]=useState(false), [highlight,setHighlight]=useState(-1);
  const [quote,setQuote]=useState<Quote|null>(null), [loaders,setLoaders]=useState(0), [pay,setPay]=useState<'cash'|'qpay'>('qpay');
  const [order,setOrder]=useState<Order|null>(null), [busy,setBusy]=useState(false), [error,setError]=useState(''), [user,setUser]=useState<any>(null), [qpay,setQpay]=useState<any>(null);
  const [panel,setPanel]=useState<'menu'|'profile'|null>(null);
  const [disconnected,setDisconnected]=useState(false);
  const socket=useRef<WebSocket|null>(null), searchTimer=useRef<ReturnType<typeof setTimeout>|null>(null), reconnectTimer=useRef<ReturnType<typeof setTimeout>|null>(null), orderDone=useRef(false);
  const staleGuard=useRef(createStaleGuard()).current, sessionToken=useRef<google.maps.places.AutocompleteSessionToken|null>(null);
  const [searched,setSearched]=useState(false), [notice,setNotice]=useState(''), [ordering,setOrdering]=useState(false);
  const searchInput=useRef<HTMLInputElement>(null);
  useEffect(()=>{if(highlight>=0)document.getElementById(`place-option-${highlight}`)?.scrollIntoView({block:'nearest'});},[highlight]);
  function updatePlaces(rows:PlaceRow[]){setPlaces(rows);setHighlight(-1)}
  const selectedPrice=quote?.prices.find(p=>p.service.id===selected);

  async function boot(){setError('');try{const [me,svcs]=await Promise.all([api<any>('/auth/me'),api<Service[]>('/services')]);setUser(me);setServices(svcs);setSelected(svcs.find(s=>s.code==='porter')?.id||svcs[0]?.id||'');setScreen('home');navigator.geolocation?.getCurrentPosition(pos=>{if(!pickupTouched.current)setPickup({...fallback,lat:pos.coords.latitude,lng:pos.coords.longitude})},()=>{}, {timeout:5000,maximumAge:300000})}catch(e){if((e as ApiError).status===401)setScreen('login');else{setError(customerError(e));setScreen('loading')}}}
  useEffect(()=>{boot();return()=>{orderDone.current=true;if(reconnectTimer.current)clearTimeout(reconnectTimer.current);socket.current?.close();if(searchTimer.current)clearTimeout(searchTimer.current);staleGuard.start()}},[]);
  useEffect(()=>{function onPop(){setScreen(current=>current==='route'?'home':current)}window.addEventListener('popstate',onPop);return()=>window.removeEventListener('popstate',onPop)},[]);
  useEffect(()=>{if(screen==='route')history.pushState({achaagoScreen:'route'},'')},[screen]);
  async function loggedIn(value:any){setUser(value);const svcs=await api<Service[]>('/services');setServices(svcs);setSelected(svcs.find(s=>s.code==='porter')?.id||svcs[0]?.id||'');setScreen('home')}
  function begin(serviceId?:string){pickupTouched.current=true;editAddress('dropoff');setNotice('');if(serviceId)setSelected(serviceId);setScreen('route');setError('')}
  function editAddress(target:'pickup'|'dropoff') {
    if(busy)return;
    pickupTouched.current=true;
    if(searchTimer.current)clearTimeout(searchTimer.current);
    staleGuard.start();sessionToken.current=null;updatePlaces([]);setPlacesLoading(false);setSearched(false);setError('');
    setAddressTarget(target);
    setSearch(target==='pickup'?(pickupReady&&pickup.address!==fallback.address?pickup.address:''):(dropoff?.address??''));
    requestAnimationFrame(()=>{searchInput.current?.focus();searchInput.current?.select();});
  }
  async function applyPlace(place:Point) {
    const nextPickup=addressTarget==='pickup'?place:pickup;
    const nextDropoff=addressTarget==='dropoff'?place:dropoff;
    if(addressTarget==='pickup'){pickupTouched.current=true;setPickup(place);setPickupReady(true)}else setDropoff(place);
    setSearch(place.address);updatePlaces([]);
    if(nextDropoff&&(addressTarget==='pickup'||pickupReady))setQuote(await api<Quote>('/quotes',{method:'POST',body:JSON.stringify({pickup:nextPickup,dropoff:nextDropoff,loaders})}));
  }
  function searchPlaces(value:string){setError('');setSearched(false);updatePlaces([]);setSearch(value);if(addressTarget==='pickup'){pickupTouched.current=true;setPickupReady(false)}else setDropoff(null);setQuote(null);if(searchTimer.current)clearTimeout(searchTimer.current);const query=value.trim();const token=staleGuard.start();if(query.length<3){updatePlaces([]);setPlacesLoading(false);sessionToken.current=null;return}setPlacesLoading(true);searchTimer.current=setTimeout(()=>runSearch(query,token),300)}
  async function runSearch(query:string,token:number){
    if(isGooglePlacesAvailable()){
      if(!sessionToken.current)sessionToken.current=createSessionToken();
      try{const results=await searchGooglePlaces(query,sessionToken.current);if(staleGuard.isCurrent(token)){updatePlaces(results.map(p=>({...p,source:'google' as const})));setPlacesLoading(false);setSearched(true)}return}catch{/* Places unavailable for this query — fall back to the demo search below. */}
    }
    try{const results=await api<{id:string;address:string}[]>('/places?q='+encodeURIComponent(query));if(staleGuard.isCurrent(token)){updatePlaces(results.map(p=>({...p,source:'demo' as const})));setPlacesLoading(false);setSearched(true)}}catch(e){if(staleGuard.isCurrent(token)){setError(customerError(e));setPlacesLoading(false)}}
  }
  function onSearchKeyDown(e:KeyboardEvent<HTMLInputElement>){
    if(e.key==='Escape'){setSearched(false);if(searchTimer.current)clearTimeout(searchTimer.current);staleGuard.start();updatePlaces([]);setPlacesLoading(false);return}
    if(!places.length)return;
    if(e.key==='ArrowDown'){e.preventDefault();setHighlight(h=>cycleHighlight(h,places.length,1))}
    else if(e.key==='ArrowUp'){e.preventDefault();setHighlight(h=>cycleHighlight(h,places.length,-1))}
    else if(e.key==='Enter'&&highlight>=0){e.preventDefault();pickPlace(places[highlight])}
  }
  async function pickPlace(row:PlaceRow){
    if(busy)return;
    if(searchTimer.current)clearTimeout(searchTimer.current);
    setSearched(false);setQuote(null);setBusy(true);setError('');
    try{staleGuard.start();setPlacesLoading(false);const place=row.source==='google'?await getGooglePlaceDetails(row.place):await api<Point>('/places/'+encodeURIComponent(row.id));sessionToken.current=null;await applyPlace(place)}
    catch(e){setError(customerError(e))}finally{setBusy(false)}
  }
  async function pickOnMap(point:{lat:number;lng:number}){
    if(busy)return;
    if(searchTimer.current)clearTimeout(searchTimer.current);
    setSearched(false);setQuote(null);setBusy(true);setError('');
    try{staleGuard.start();sessionToken.current=null;setPlacesLoading(false);let address:string=copy.mapPoint;try{address=await reverseGeocode(point)}catch{}await applyPlace({...point,address})}
    catch(e){setError(customerError(e))}finally{setBusy(false)}
  }
  async function useCurrentLocation(){
    if(busy)return;
    if(searchTimer.current)clearTimeout(searchTimer.current);
    staleGuard.start();sessionToken.current=null;updatePlaces([]);setPlacesLoading(false);setSearched(false);setBusy(true);setError('');setQuote(null);
    try{
      const position=await new Promise<GeolocationPosition>((resolve,reject)=>{
        if(!navigator.geolocation){reject(new Error('unavailable'));return}
        navigator.geolocation.getCurrentPosition(resolve,reject,{timeout:10000,maximumAge:0});
      });
      const point={lat:position.coords.latitude,lng:position.coords.longitude};
      let address=fallback.address;try{address=await reverseGeocode(point)}catch{}
      await applyPlace({...point,address});
    }catch(e){setError(e instanceof ApiError?customerError(e):copy.locationFailed)}finally{setBusy(false)}
  }
  async function requote(nextLoaders:number){if(busy)return;setLoaders(nextLoaders);if(!dropoff||!pickupReady)return;setError('');setBusy(true);try{setQuote(await api('/quotes',{method:'POST',body:JSON.stringify({pickup,dropoff,loaders:nextLoaders})}))}catch(e){setQuote(null);setError(customerError(e))}finally{setBusy(false)}}
  async function placeOrder(){if(busy||!pickupReady||!dropoff||!quote||!selectedPrice)return;setOrdering(true);setBusy(true);setError('');try{const value=await api<Order>('/orders',{method:'POST',headers:{'Idempotency-Key':uuid()},body:JSON.stringify({pickup,dropoff,loaders,service_id:selected,payment_method:pay,expected_total:selectedPrice.breakdown.total,quote_token:quote.quote_token})});setOrder(value);setScreen(value.status==='assigned'?'tracking':'finding');watch(value)}catch(e){if((e as ApiError).code==='QUOTE_CHANGED'&&dropoff)setQuote(await api('/quotes',{method:'POST',body:JSON.stringify({pickup,dropoff,loaders})}));setError(customerError(e))}finally{setBusy(false);setOrdering(false)}}
  function watch(value:Order){orderDone.current=false;setDisconnected(false);if(reconnectTimer.current){clearTimeout(reconnectTimer.current);reconnectTimer.current=null}socket.current?.close();connectOrderSocket(value.id)}
  function connectOrderSocket(orderId:string){
    const scheme=location.protocol==='https:'?'wss:':'ws:';
    const ws=new WebSocket(`${scheme}//${location.host}/ws/orders/${orderId}`);
    socket.current=ws;
    ws.onopen=()=>setDisconnected(false);
    ws.onmessage=event=>{const data=JSON.parse(event.data);if(data.type==='snapshot'){const fresh=data.order as Order;setOrder(fresh);if(['assigned','driver_arriving','arrived','picked_up','delivered'].includes(fresh.status)){setScreen('tracking');if(fresh.status==='assigned'){navigator.vibrate?.([120,80,120])}}if(fresh.status==='completed'){orderDone.current=true;setScreen('complete')}if(['cancelled','no_driver_found'].includes(fresh.status)){orderDone.current=true;setNotice(fresh.status==='cancelled'?copy.cancelled:copy.noDriver);setScreen('home')}}};
    ws.onclose=()=>{if(orderDone.current||socket.current!==ws)return;setDisconnected(true);reconnectTimer.current=setTimeout(()=>connectOrderSocket(orderId),2000)};
    ws.onerror=()=>ws.close();
  }
  async function cancel(){if(busy||!order||!confirm('Захиалгаа цуцлах уу?'))return;setBusy(true);setError('');try{await api(`/orders/${order.id}/cancel`,{method:'POST',body:JSON.stringify({reason:'Хэрэглэгч цуцалсан'})});orderDone.current=true;if(reconnectTimer.current){clearTimeout(reconnectTimer.current);reconnectTimer.current=null}socket.current?.close();setOrder(null);setNotice(copy.cancelled);setScreen('home')}catch(e){setError(customerError(e))}finally{setBusy(false)}}
  async function showQpay(){if(busy||!order)return;setError('');setBusy(true);try{setQpay(await api(`/orders/${order.id}/qpay-invoice`,{method:'POST',body:'{}'}))}catch(e){setError(customerError(e))}finally{setBusy(false)}}
  async function submitRating(value:number){if(busy||!order)return;setBusy(true);setError('');try{await api(`/orders/${order.id}/rating`,{method:'POST',body:JSON.stringify({rating:value})});setOrder({...order,rating:value})}catch(e){setError(customerError(e))}finally{setBusy(false)}}
  if(screen==='loading')return <main className="phone customer-screen flow-loading"><div role="status">{error ? <><p>{error}</p><button className="btn btn-accent" onClick={boot}>{copy.retry}</button></> : <><span className="spinner" aria-hidden="true"/><p>{copy.loading}</p></>}</div></main>;
  if(screen==='login')return <PhoneLogin onDone={loggedIn}/>;

  if(screen==='home')return <main className="phone customer-screen">
    <div className="map-stage home-map"><GoogleMapView pickup={pickup}/><div className="map-toolbar"><button className="icon-btn" aria-label="Цэс" aria-haspopup="dialog" aria-expanded={panel==='menu'} aria-controls={panel==='menu'?'customer-panel':undefined} onClick={()=>setPanel('menu')}><Menu aria-hidden="true"/></button><button className="icon-btn" aria-label="Профайл" aria-haspopup="dialog" aria-expanded={panel==='profile'} aria-controls={panel==='profile'?'customer-panel':undefined} onClick={()=>setPanel('profile')}><UserRound aria-hidden="true"/></button></div></div>
    <section className="sheet booking-sheet" aria-labelledby="home-title">
      <div className="booking-handle" aria-hidden="true"/>
      <span className="muted">Сайн байна уу{user?.name?`, ${user.name}`:''}</span>
      <h1 id="home-title" className="display">Юу ачуулах вэ?</h1>
      {notice&&<p className="status-card" role="status">{notice}</p>}
      <button className="btn home-search" disabled={!services.length} onClick={()=>begin(services.find(s=>s.code==='porter')?.id)}><Search size={20} aria-hidden="true"/>Хаашаа ачих вэ?<ChevronRight size={18} aria-hidden="true" style={{marginLeft:'auto'}}/></button>
      <div className="service-grid desktop-vehicle-selector">{services.map(s=><button className="service-card" key={s.id} onClick={()=>begin(s.id)}><span className="service-icon" aria-hidden="true"><ServiceIcon type={s.icon}/></span><strong className="display">{s.name_mn}</strong><small className="muted">{s.description_mn}</small><b className="service-price">{copy.basePrice} {money(s.base_fare)}</b></button>)}</div>
      <VehicleCards services={services} onSelect={begin} home/>
      {!services.length&&<div className="status-card" role="status"><p>{copy.noServices}</p><button className="btn btn-outline" onClick={boot}>{copy.retry}</button></div>}
    </section>
    {panel&&<CustomerPanel kind={panel} customer={user} hasActiveOrder={!!order&&['pending','assigned','driver_arriving','arrived','picked_up','delivered'].includes(order.status)} onClose={()=>setPanel(null)}/>}
  </main>;

  if(screen==='route')return <main className="phone customer-screen route-screen">
    <section className="route-search" aria-labelledby="route-title">
      <div className="route-heading"><button className="icon-btn" disabled={busy} onClick={()=>setScreen('home')} aria-label="Буцах"><ArrowLeft aria-hidden="true"/></button><div><h1 id="route-title" className="display">Хаашаа ачих вэ?</h1><small>{addressTarget==='pickup'?copy.editingPickup:copy.editingDestination}</small></div></div>
      <div className="address-targets" role="group" aria-label={copy.addressTarget}>
        <button type="button" disabled={busy} aria-pressed={addressTarget==='pickup'} onClick={()=>editAddress('pickup')}>{copy.pickupLabel}</button>
        <button type="button" disabled={busy} aria-pressed={addressTarget==='dropoff'} onClick={()=>editAddress('dropoff')}>{copy.destinationLabel}</button>
      </div>
      <label className="sr-only" htmlFor="destination">{addressTarget==='pickup'?copy.pickupLabel:copy.destinationLabel}</label>
      <div className="destination-field"><MapPin size={20} aria-hidden="true"/><input ref={searchInput} id="destination" value={search} disabled={busy} onChange={e=>searchPlaces(e.target.value)} onKeyDown={onSearchKeyDown} placeholder={addressTarget==='pickup'?copy.searchPickup:copy.searchDestination} role="combobox" aria-expanded={places.length>0} aria-controls={places.length>0?'destination-listbox':undefined} aria-autocomplete="list" aria-describedby="search-feedback" aria-activedescendant={highlight>=0&&places[highlight]?`place-option-${highlight}`:undefined} autoComplete="off"/>{search&&<button className="clear-search" disabled={busy} aria-label={addressTarget==='pickup'?copy.clearPickup:copy.clearDestination} onClick={()=>{searchPlaces('');searchInput.current?.focus()}}><X size={18} aria-hidden="true"/></button>}</div>
      <p id="search-feedback" className="search-feedback" role="status">{placesLoading?copy.searching:busy?copy.quoteLoading:(addressTarget==='pickup'?pickupReady:!!dropoff)?(addressTarget==='pickup'?copy.selectedPickup:copy.selectedAddress):searched&&!places.length&&!error?copy.noResults:search.trim().length>0&&search.trim().length<3?copy.searchShort:copy.searchHelp}</p>
      {addressTarget==='pickup'&&<button type="button" className="text-button current-pickup" disabled={busy} onClick={useCurrentLocation}>{copy.useCurrentLocation}</button>}
      {places.length>0&&<div id="destination-listbox" role="listbox" aria-label={addressTarget==='pickup'?copy.pickupSuggestions:copy.destinationSuggestions} className="suggest-list">{places.map((p,index)=><button className="suggest-option" key={p.id} id={`place-option-${index}`} role="option" aria-selected={index===highlight} disabled={busy} onMouseEnter={()=>setHighlight(index)} onClick={()=>pickPlace(p)}><MapPin size={18} aria-hidden="true"/><span>{p.address}</span></button>)}</div>}
    </section>
    <div className="map-stage"><GoogleMapView route={pickupReady&&!!dropoff} routePolyline={quote?.polyline} pickup={pickupReady?pickup:null} dropoff={dropoff} onPick={pickOnMap}/></div>
    <section className="sheet booking-sheet" aria-labelledby="service-title">
      <div className="booking-handle" aria-hidden="true"/>
      <dl className="booking-addresses">
        <div className="booking-stop pickup-stop"><dt>{copy.pickupLabel}</dt><dd>{pickupReady?pickup.address:copy.needsPickup}<button type="button" className="address-edit" disabled={busy} onClick={()=>editAddress('pickup')} aria-label={copy.changePickup}>{copy.changeAddress}</button></dd></div>
        <div className="booking-stop destination-stop"><dt>{copy.destinationLabel}</dt><dd>{dropoff?.address??copy.destinationPending}<button type="button" className="address-edit" disabled={busy} onClick={()=>editAddress('dropoff')} aria-label={copy.changeDestination}>{copy.changeAddress}</button></dd></div>
      </dl>
      {dropoff&&<div className="selected-address desktop-vehicle-selector"><MapPin size={19} aria-hidden="true"/><div><small>{copy.selectedAddress}</small><strong>{dropoff.address}</strong></div></div>}
      <div className="section-heading"><h2 id="service-title" className="display">Машинаа сонго</h2>{quote&&<span className="muted">{quote.distance_km} км · ~{quote.duration_minutes} мин</span>}</div>
      <div className="service-options desktop-vehicle-selector">{(quote?.prices||services.map(service=>({service,breakdown:{total:service.base_fare}}))).map(p=><button className="service-option" key={p.service.id} disabled={busy} onClick={()=>setSelected(p.service.id)} aria-pressed={selected===p.service.id}><span className="service-icon" aria-hidden="true"><ServiceIcon type={p.service.icon}/></span><span className="service-description"><b>{p.service.name_mn}</b><small>{p.service.description_mn}</small></span><span className="service-amount">{!quote&&<small>{copy.basePrice}</small>}<b>{money(p.breakdown.total)}</b></span></button>)}</div>
      <VehicleCards services={services} quote={quote} selected={selected} busy={busy} onSelect={setSelected}/>
      <label className="loader-option"><span><b>Ачигч нэмэх</b><small>+{money(quote?.loader_rate??25000)}</small></span><input type="checkbox" checked={loaders>0} disabled={busy} onChange={e=>requote(e.target.checked?1:0)}/></label>
      <fieldset className="payment-options" disabled={busy}><legend>{copy.payment}</legend><div>{([['qpay','QPay'],['cash','Бэлэн мөнгө']] as const).map(([id,label])=><button key={id} className="btn" aria-pressed={pay===id} onClick={()=>setPay(id)}>{label}</button>)}</div></fieldset>
      <div className="order-action">
        {error&&<p className="error" role="alert">{error}</p>}
        {pickupReady&&dropoff&&!quote&&!busy&&<button className="btn btn-outline" onClick={()=>requote(loaders)}>{copy.retryQuote}</button>}
        <button className="btn btn-accent" disabled={!pickupReady||!dropoff||!quote||!selectedPrice||busy} aria-describedby="order-help" onClick={placeOrder}>{busy&&<span className="spinner" aria-hidden="true"/>}{busy?(ordering?copy.orderLoading:copy.quoteLoading):selectedPrice?`${selectedPrice.service.name_mn} захиалах · ${money(selectedPrice.breakdown.total)}`:copy.order}</button>
        <p id="order-help" className="order-help" role="status">{busy?(ordering?copy.orderLoading:copy.quoteLoading):!pickupReady?copy.needsPickup:!dropoff?copy.needsAddress:!quote?copy.needsQuote:'Захиалгын нийт үнэ дээр харагдаж байна.'}</p>
      </div>
    </section>
  </main>;

  if((screen==='finding'||screen==='tracking')&&order)return <main className="phone customer-screen">
    <div className="map-stage"><GoogleMapView route routePolyline={order.polyline} pulse={screen==='finding'} truck={screen==='tracking'} pickup={pickup} dropoff={dropoff} driverLocation={order.driver?.location??null}/></div>
    <section className="sheet">
      {screen==='finding'?<><h1 className="display" role="status">Жолооч хайж байна…</h1><p className="muted">Ойролцоох {order.service_name} жолооч нарт захиалгыг илгээлээ.</p><div aria-hidden="true" style={{height:6,background:'var(--line)',borderRadius:3,marginBottom:16}}><div className="pulse" style={{width:'42%',height:'100%',background:'var(--accent)',borderRadius:3}}/></div></>:<>
        <div className="section-heading"><div><small className="muted" role="status">{mn.statuses[order.status]}</small><h1 className="display" style={{fontSize:24,margin:2}}>~{order.duration_minutes} мин</h1></div><strong className="badge">{order.driver?.plate_number||'—'}</strong></div>
        <div style={{display:'flex',alignItems:'center',gap:13,marginBottom:14}}><span className="service-icon" aria-hidden="true">{order.driver?.name?.slice(0,2).toUpperCase()||'Ж'}</span><div style={{flex:1,minWidth:0}}><b>{order.driver?.name||'Жолооч'}</b><span className="muted" style={{display:'flex',gap:5,alignItems:'center',marginTop:3}}><Star size={15} fill="var(--accent)" aria-hidden="true"/>{order.driver?.rating||'Шинэ'} · {order.service_name}</span></div></div>
        <div style={{display:'grid',gridTemplateColumns:'1fr 1fr',gap:10,marginBottom:14}}><a className="btn btn-accent" href={order.driver?.phone?`tel:${order.driver.phone}`:'#'}><Phone size={19} aria-hidden="true"/>Залгах</a><a className="btn btn-outline" href={order.driver?.phone?`sms:${order.driver.phone}`:'#'}><MessageSquare size={19} aria-hidden="true"/>Мессеж</a></div>
      </>}
      {disconnected&&<p className="status-card" role="status">{copy.reconnecting}</p>}
      <Summary order={order}/>
      {order.payment_method==='qpay'&&screen==='tracking'&&order.payment_status!=='paid'&&<button className="btn btn-primary" disabled={busy} style={{width:'100%',marginTop:12}} onClick={showQpay}>{busy?copy.qpayLoading:'QPay төлбөр төлөх'}</button>}
      {error&&<p className="error" role="alert" style={{marginTop:12}}>{error}</p>}
      {order.can_cancel&&<button className="btn btn-outline" disabled={busy} style={{width:'100%',marginTop:12}} onClick={cancel}>Захиалга цуцлах</button>}
      <p className="sr-only" role="status">{busy?copy.loading:''}</p>
    </section>
    {qpay&&<QpayDialog invoice={qpay} onClose={()=>setQpay(null)}/>}
  </main>;

  if(screen==='complete'&&order)return <main className="phone customer-screen" style={{padding:24,justifyContent:'center',textAlign:'center',gap:18}}>
    <span style={{width:80,height:80,borderRadius:'50%',background:'var(--accent)',display:'grid',placeItems:'center',margin:'0 auto'}}><Check size={44} aria-hidden="true"/></span>
    <h1 className="display" style={{fontSize:24,margin:0}}>Ачаа хүргэгдлээ</h1><p className="muted" style={{margin:0}}>Манай үйлчилгээг сонгосонд баярлалаа.</p>
    <Summary order={order}/><p id="rating-label" style={{fontWeight:600,margin:0}}>Жолоочийн үйлчилгээг үнэлнэ үү</p>
    <div className="rating-buttons" role="group" aria-labelledby="rating-label">{[1,2,3,4,5].map(value=><button key={value} disabled={busy} aria-label={`${value} од`} aria-pressed={order.rating===value} onClick={()=>submitRating(value)}><Star size={32} aria-hidden="true" fill={(order.rating||0)>=value?'var(--accent)':'none'} color="var(--ink)"/></button>)}</div>
    <p role="status" className="muted" style={{margin:0}}>{busy?copy.ratingSaving:order.rating?copy.ratingSaved:''}</p>
    {error&&<p className="error" role="alert">{error}</p>}
    <button className="btn btn-primary" disabled={busy} onClick={()=>{setOrder(null);setError('');setScreen('home')}}>Шинэ захиалга</button>
  </main>;
  return null;
}
