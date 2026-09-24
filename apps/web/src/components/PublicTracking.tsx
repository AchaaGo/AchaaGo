'use client';
import {useEffect,useState} from 'react';
import {Star,Truck} from 'lucide-react';
import {api,Order} from '@/lib/api';
import {mn} from '@/lib/messages';
import {GoogleMapView} from './GoogleMapView';

export function PublicTracking({token}:{token:string}){
 const [order,setOrder]=useState<Order|null>(null),[error,setError]=useState('');
 useEffect(()=>{let ws:WebSocket|undefined;api<Order>('/t/'+encodeURIComponent(token)).then(value=>{setOrder(value);const scheme=location.protocol==='https:'?'wss:':'ws:';ws=new WebSocket(`${scheme}//${location.host}/ws/tracking/${encodeURIComponent(token)}`);ws.onmessage=e=>{const data=JSON.parse(e.data);if(data.type==='snapshot')setOrder(data.order)}}).catch(e=>setError(e.message));return()=>ws?.close()},[token]);
 if(error)return <main className="phone customer-screen" style={{display:'grid',placeItems:'center',padding:28,textAlign:'center'}}><div><h1 className="display">Холбоос идэвхгүй</h1><p className="muted">{error}</p></div></main>;
 if(!order)return <main className="phone customer-screen" style={{display:'grid',placeItems:'center',background:'var(--ink)'}}><div role="status" style={{color:"white",textAlign:"center"}}><span className="spinner" aria-hidden="true"/><p>Захиалгын мэдээллийг ачаалж байна…</p></div></main>;
 return <main className="phone customer-screen"><div className="map-stage"><GoogleMapView route truck={!!order.driver} pickup={order.pickup} dropoff={order.dropoff} driverLocation={order.driver?.location??null}/></div><section className="sheet"><div className="grab"/><span className="badge">{mn.statuses[order.status]||'Захиалгын мэдээлэл'}</span><h1 className="display" style={{fontSize:22}}>Захиалгын явц</h1>{order.driver&&<div className="card" style={{padding:14,display:'flex',alignItems:'center',gap:12,marginBottom:14}}><span style={{width:48,height:48,borderRadius:'50%',background:'var(--ink)',color:'var(--accent)',display:'grid',placeItems:'center'}}><Truck/></span><div style={{flex:1}}><b>{order.driver.name}</b><span className="muted" style={{display:'flex',alignItems:'center',gap:4}}><Star size={14} fill="var(--accent)"/>{order.driver.rating||'Шинэ'}</span></div><strong>{order.driver.plate_number}</strong></div>}<div style={{display:'grid',gap:12,padding:16,background:'var(--ground)',borderRadius:16}}><div><small className="muted">Авах</small><div>{order.pickup.address}</div></div><div><small className="muted">Хүргэх</small><div>{order.dropoff.address}</div></div><div style={{display:'flex',justifyContent:'space-between'}}><span>{order.service_name}</span><span>{order.distance_km} км</span></div></div><p className="muted" style={{fontSize:13,textAlign:'center'}}>Энэхүү холбоос нь утасны дугаар болон төлбөрийн мэдээлэл харуулахгүй.</p></section></main>
}
