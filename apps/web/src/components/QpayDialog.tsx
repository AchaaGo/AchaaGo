'use client';
import {useEffect, useRef} from 'react';
import {X} from 'lucide-react';
import {money} from '@/lib/api';

// Native modal semantics provide focus containment, Escape, and focus restoration.
export function QpayDialog({invoice, onClose}:{invoice:any; onClose:()=>void}) {
  const dialog = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const element = dialog.current;
    element?.showModal();
    return () => element?.close();
  }, []);
  return <dialog ref={dialog} className="qpay-dialog" aria-labelledby="qpay-title" onCancel={onClose}>
    <button autoFocus className="icon-btn" onClick={onClose} aria-label="Хаах" style={{marginLeft:'auto',boxShadow:'none'}}><X aria-hidden="true"/></button>
    <h2 id="qpay-title" className="display">QPay</h2>
    <p>{money(invoice.amount)}</p>
    {invoice.demo ? <p className="muted">Туршилтын горимд бодит төлбөр хийгдэхгүй.</p> : invoice.qr_image ? <img src={`data:image/png;base64,${invoice.qr_image}`} alt="QPay төлбөрийн QR код" style={{width:220,maxWidth:'100%'}}/> : null}
    {invoice.urls?.map((url:any) => <a key={url.link} className="btn btn-accent" style={{width:'100%',marginTop:8}} href={url.link}>{url.description || 'QPay нээх'}</a>)}
  </dialog>;
}
