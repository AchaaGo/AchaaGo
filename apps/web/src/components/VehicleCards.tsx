import {Check} from 'lucide-react';
import {money, type Quote, type Service} from '@/lib/api';
import {customerCopy as copy} from './customerCopy';

// Local vectors share the same side view, baseline, stroke and brand palette.
function VehicleIllustration({code}:{code:string}) {
  return <svg viewBox="0 0 112 72" fill="none" aria-hidden="true" focusable="false">
    <g stroke="var(--ink-deep)" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
      <path d="M8 63h96" stroke="var(--line)"/>
      {code==='motorcycle' ? <>
        <circle cx="28" cy="53" r="10" fill="white"/><circle cx="86" cy="53" r="10" fill="white"/>
        <path d="m28 53 17-24 16 24H28l22-13h25l-9-22h12"/>
        <path d="m73 35 13 18M40 28h20"/>
        <path d="M47 33h15l8 11H42z" fill="var(--accent-soft)"/>
        <rect x="16" y="17" width="23" height="20" rx="3" fill="var(--accent-soft)"/>
        <path d="M27 18v7" stroke="var(--accent)"/>
      </> : code==='amjirgaa' ? <>
        <path d="M12 49V26a7 7 0 0 1 7-7h54l18 17 8 4v14H12z" fill="var(--accent-soft)"/>
        <path d="M65 25h7l13 13H65z" fill="white"/><path d="M21 25h34v13H21z" fill="white"/>
        <path d="M60 21v31M67 43h6"/><path d="M94 43h4" stroke="var(--accent)"/>
        <circle cx="30" cy="53" r="9" fill="white"/><circle cx="81" cy="53" r="9" fill="white"/>
      </> : <>
        <path d="M10 29h53v23H10z" fill="var(--accent-soft)"/>
        <path d="M63 20h20l16 21v13H63z" fill="var(--accent-soft)"/>
        <path d="M70 26h10l10 14H70z" fill="white"/>
        <path d="M17 35h39M70 45h5"/><path d="M95 46h4" stroke="var(--accent)"/>
        <circle cx="29" cy="53" r="9" fill="white"/><circle cx="81" cy="53" r="9" fill="white"/>
      </>}
    </g>
  </svg>;
}

export function VehicleCards({services,quote,selected,busy=false,onSelect,home=false}:{
  services:Service[];quote?:Quote|null;selected?:string;busy?:boolean;onSelect:(id:string)=>void;home?:boolean;
}) {
  const rows=(quote?.prices.map(price=>price.service)??services).slice().sort((a,b)=>a.sort_order-b.sort_order);
  return <div className="mobile-vehicle-selector" role="group" aria-label={copy.chooseVehicle} aria-busy={busy}>
    {rows.map(service=>{
      const price=quote?.prices.find(row=>row.service.id===service.id);
      const details=copy.vehicleDetails[service.code as keyof typeof copy.vehicleDetails];
      const active=!home&&selected===service.id;
      return <button type="button" key={service.id} className="vehicle-card" disabled={busy}
        aria-pressed={home?undefined:active} onClick={()=>onSelect(service.id)}>
        <span className="vehicle-art"><VehicleIllustration code={service.code}/></span>
        <span className="vehicle-body">
          <span className="vehicle-title"><strong>{service.name_mn}</strong>{service.code==='motorcycle'&&<span className="vehicle-badge">{copy.express}</span>}</span>
          <span className="vehicle-description">{details?.description??service.description_mn}</span>
          {details?.hint&&<span className="vehicle-hint">{details.hint}</span>}
          <span className="vehicle-price">{busy?copy.priceUpdating:price?money(price.breakdown.total):copy.priceAfterRoute}</span>
        </span>
        {!home&&<span className="vehicle-check" aria-hidden="true">{active&&<Check size={14}/>}</span>}
      </button>;
    })}
  </div>;
}
