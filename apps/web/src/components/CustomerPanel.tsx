'use client';
import {useEffect,useRef,useState,type MouseEvent} from 'react';
import {ClipboardList,MapPin,HelpCircle,FileText,Truck,UserRound,LogOut,X,type LucideIcon} from 'lucide-react';
import {api,ApiError,phoneFmt} from '@/lib/api';
import {customerCopy as copy} from './customerCopy';

type Props={kind:'menu'|'profile';customer:{name?:string|null;phone?:string|null}|null;hasActiveOrder:boolean;onClose:()=>void};

export function CustomerPanel({kind,customer,hasActiveOrder,onClose}:Props){
  const dialog=useRef<HTMLDialogElement>(null);
  const [loggingOut,setLoggingOut]=useState(false),[error,setError]=useState('');
  useEffect(()=>{
    const element=dialog.current;
    const previous=document.activeElement instanceof HTMLElement?document.activeElement:null;
    const overflow=document.body.style.overflow;
    document.body.style.overflow='hidden';
    element?.showModal();
    return()=>{element?.close();document.body.style.overflow=overflow;if(previous?.isConnected)previous.focus({preventScroll:true})};
  },[]);
  function backdropClick(event:MouseEvent<HTMLDialogElement>){
    if(event.target!==event.currentTarget)return;
    const bounds=event.currentTarget.getBoundingClientRect();
    if(event.clientX<bounds.left||event.clientX>bounds.right||event.clientY<bounds.top||event.clientY>bounds.bottom)onClose();
  }
  async function logout(){
    if(loggingOut)return;
    setLoggingOut(true);setError('');
    try{await api('/auth/logout',{method:'POST',body:'{}'});location.reload()}
    catch(error){setError(error instanceof ApiError?error.message:copy.error);setLoggingOut(false)}
  }
  const name=customer?.name?.trim();
  const rawPhone=customer?.phone??'';
  const phone=/^\+976\d{8}$/.test(rawPhone)?'+976 '+phoneFmt(rawPhone.slice(4)):rawPhone;
  const rows:{label:string;Icon:LucideIcon;active?:boolean}[]=kind==='menu'
    ? [{label:copy.myOrders,Icon:ClipboardList,active:hasActiveOrder},{label:copy.savedAddresses,Icon:MapPin},{label:copy.help,Icon:HelpCircle}]
    : [{label:copy.personalInfo,Icon:UserRound},{label:copy.savedAddresses,Icon:MapPin},{label:copy.help,Icon:HelpCircle}];
  return <dialog ref={dialog} id="customer-panel" className="customer-panel" aria-modal="true" aria-labelledby="customer-panel-title" onClick={backdropClick} onCancel={event=>{event.preventDefault();onClose()}}>
    <div className="customer-panel-handle" aria-hidden="true"/>
    <header className="customer-panel-header"><h2 id="customer-panel-title">{kind==='menu'?copy.menu:copy.profile}</h2><button autoFocus type="button" className="customer-panel-close" aria-label={copy.closePanel} onClick={onClose}><X size={22} aria-hidden="true"/></button></header>
    {kind==='profile'&&<div className="customer-panel-identity"><strong>{name||phone||copy.phoneUnavailable}</strong>{name&&phone&&<span>{phone}</span>}</div>}
    <nav aria-label={kind==='menu'?copy.menu:copy.profile}>
      {rows.map(({label,Icon,active})=><button key={label} type="button" className="customer-panel-row" disabled><Icon size={20} aria-hidden="true"/><span className="customer-panel-label">{label}{active&&<><span className="customer-order-dot" aria-hidden="true"/><span className="sr-only"> — {copy.activeOrder}</span></>}</span><small>{copy.comingSoon}</small></button>)}
      <a className="customer-panel-row" href="/terms" target="_blank" rel="noopener noreferrer"><FileText size={20} aria-hidden="true"/><span className="customer-panel-label">{copy.terms}<span className="sr-only"> — {copy.newWindow}</span></span></a>
      {kind==='menu'&&<button type="button" className="customer-panel-row" disabled><Truck size={20} aria-hidden="true"/><span className="customer-panel-label">{copy.becomeDriver}</span><small>{copy.comingSoon}</small></button>}
      <button type="button" className="customer-panel-row customer-panel-logout" disabled={loggingOut} onClick={logout}><LogOut size={20} aria-hidden="true"/><span>{loggingOut?copy.loggingOut:copy.logout}</span></button>
    </nav>
    {error&&<p className="customer-panel-error" role="alert">{error}</p>}
    <span className="sr-only" role="status">{loggingOut?copy.loggingOut:''}</span>
  </dialog>;
}
