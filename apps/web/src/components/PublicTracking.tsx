'use client';
import {useEffect,useState} from 'react';
import {Star,Truck} from 'lucide-react';
import {api,Order} from '@/lib/api';
import {mn} from '@/lib/messages';
import {GoogleMapView} from './GoogleMapView';

const FINISHED=['completed','cancelled','no_driver_found'];

export function PublicTracking({token}:{token:string}){
 const [order,setOrder]=useState<Order|null>(null),[error,setError]=useState('');
 useEffect(()=>{
  // Shared links are mostly opened on phones, where sockets drop often: reconnect until the order is finished.
  let ws:WebSocket|undefined,timer:ReturnType<typeof setTimeout>|undefined,stopped=false;
  const connect=()=>{const scheme=location.protocol==='https:'?'wss:':'ws:';const socket=new WebSocket(`${scheme}//${location.host}/ws/tracking/${encodeURIComponent(token)}`);ws=socket;
   socket.onmessage=e=>{let data:any;try{data=JSON.parse(e.data)}catch{return}if(data.type==='snapshot'){setOrder(data.order);if(FINISHED.includes(data.order.status))stopped=true}};
   socket.onclose=()=>{if(!stopped&&ws===socket)timer=setTimeout(connect,3000)};socket.onerror=()=>socket.close()};
  api<Order>('/t/'+encodeURIComponent(token)).then(value=>{if(stopped)return;setOrder(value);if(!FINISHED.includes(value.status))connect()}).catch(e=>setError(e.message));
  return()=>{stopped=true;if(timer)clearTimeout(timer);ws?.close()}},[token]);
 if(error)return <main className="phone customer-screen" style={{display:'grid',placeItems:'center',padding:28,textAlign:'center'}}><div><h1 className="display">Холбоос идэвхгүй</h1><p className="muted">{error}</p></div></main>;
 if(!order)return <main className="phone customer-screen" style={{display:'grid',placeItems:'center',background:'var(--solid-ink)'}}><div role="status" style={{color:"white",textAlign:"center"}}><span className="spinner" aria-hidden="true"/><p>Захиалгын мэдээллийг ачаалж байна…</p></div></main>;
 return <main className="phone customer-screen"><div className="map-stage"><GoogleMapView route routePolyline={order.polyline} truck={!!order.driver} pickup={order.pickup} dropoff={order.dropoff} driverLocation={order.driver?.location??null}/></div><section className="sheet"><div className="grab"/><span className="badge">{mn.statuses[order.status]||'Захиалгын мэдээлэл'}</span><h1 className="display" style={{fontSize:22}}>Захиалгын явц</h1>{order.driver&&<div className="card" style={{padding:14,display:'flex',alignItems:'center',gap:12,marginBottom:14}}><span style={{width:48,height:48,borderRadius:'50%',background:'var(--solid-ink)',color:'var(--accent)',display:'grid',placeItems:'center'}}><Truck/></span><div style={{flex:1}}><b>{order.driver.name}</b><span className="muted" style={{display:'flex',alignItems:'center',gap:4}}><Star size={14} fill="var(--accent)"/>{order.driver.rating||'Шинэ'}</span></div><strong>{order.driver.plate_number}</strong></div>}<div style={{display:'grid',gap:12,padding:16,background:'var(--ground)',borderRadius:16}}><div><small className="muted">Авах</small><div>{order.pickup.address}</div></div><div><small className="muted">Хүргэх</small><div>{order.dropoff.address}</div></div><div style={{display:'flex',justifyContent:'space-between'}}><span>{order.service_name}</span><span>{order.distance_km} км</span></div></div><p className="muted" style={{fontSize:13,textAlign:'center'}}>Энэхүү холбоос нь утасны дугаар болон төлбөрийн мэдээлэл харуулахгүй.</p></section></main>
}
