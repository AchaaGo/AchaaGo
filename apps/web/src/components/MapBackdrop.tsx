import {Truck} from 'lucide-react';
export function MapBackdrop({route=false,pulse=false,truck=false}:{route?:boolean;pulse?:boolean;truck?:boolean}) {
  return <div className="map" aria-label="Газрын зураг"><div className={'pin '+(pulse?'pulse':'')}/>{route&&<svg className="route" viewBox="0 0 390 844" preserveAspectRatio="none" aria-hidden><path d="M172 345L165 280 307 265 306 202" stroke="white" strokeWidth="11" fill="none" strokeLinecap="round"/><path d="M172 345L165 280 307 265 306 202" stroke="#14213D" strokeWidth="5" fill="none" strokeLinecap="round"/><rect x="297" y="192" width="18" height="18" fill="#F2A516" stroke="#14213D" strokeWidth="3"/></svg>}{truck&&<div className="pin truck-pin"><Truck size={23}/></div>}</div>
}
