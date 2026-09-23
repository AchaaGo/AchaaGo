'use client';
import {useEffect, useRef, useState} from 'react';
import {ArrowLeft, Route} from 'lucide-react';
import {api, ApiError, phoneFmt} from '@/lib/api';
import {Brand} from './Brand';
import {customerCopy as copy} from './customerCopy';

export function PhoneLogin({onDone, heading}:{onDone:(user:any)=>void | Promise<void>;heading?:string}) {
  const [step, setStep] = useState<'phone'|'code'>('phone');
  const [phone, setPhone] = useState('');
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [seconds, setSeconds] = useState(0);
  const codeInput = useRef<HTMLInputElement>(null);
  useEffect(() => {
    if (!seconds) return;
    const id = setInterval(() => setSeconds(v => Math.max(0, v - 1)), 1000);
    return () => clearInterval(id);
  }, [seconds]);
  useEffect(() => { if (step === 'code' && !busy) codeInput.current?.focus(); }, [step, busy]);

  async function request() {
    if (busy || phone.length !== 8) return;
    setBusy(true); setError('');
    try {
      await api('/auth/otp/request', {method:'POST', body:JSON.stringify({phone:'+976'+phone})});
      setCode(''); setStep('code'); setSeconds(60);
    } catch (e) { setError(e instanceof ApiError ? e.message : copy.error); }
    finally { setBusy(false); }
  }
  async function verify() {
    // Preserve the existing two-digit test OTP contract.
    if (busy || code.length !== 2) return;
    setBusy(true); setError('');
    try {
      const value = await api<{user:any}>('/auth/otp/verify', {method:'POST', body:JSON.stringify({phone:'+976'+phone, code})});
      await onDone(value.user);
    } catch (e) { setError(e instanceof ApiError ? e.message : copy.error); }
    finally { setBusy(false); }
  }

  if (step === 'code') return <main className="phone auth-screen code-screen">
    <button className="icon-btn" aria-label="Утасны дугаар руу буцах" disabled={busy} onClick={() => {setStep('phone'); setError('');}}><ArrowLeft aria-hidden="true"/></button>
    <div><h1 className="display">Кодоо оруулна уу</h1><p className="muted">+976 {phoneFmt(phone)} дугаарт илгээсэн кодыг оруулна уу.</p></div>
    <form className="auth-form" onSubmit={e => {e.preventDefault(); void verify();}} aria-busy={busy}>
      <label className="field-label" htmlFor="otp">Баталгаажуулах код</label>
      <input ref={codeInput} id="otp" className="field otp-field" type="text" inputMode="numeric" autoComplete="one-time-code" maxLength={2} value={code} disabled={busy} onChange={e => {setCode(e.target.value.replace(/\D/g,'').slice(0,2)); setError('');}} placeholder="00" aria-describedby={error ? 'otp-help auth-error' : 'otp-help'} aria-invalid={!!error}/>
      <p id="otp-help" className="field-help">{copy.codeHelp}</p>
      {error && <p id="auth-error" className="error" role="alert">{error}</p>}
      <button type="button" className="text-button resend-button" onClick={request} disabled={seconds > 0 || busy}>{seconds ? `Дахин илгээх · ${seconds} сек` : 'Код дахин илгээх'}</button>
      <button className="btn btn-primary" disabled={code.length !== 2 || busy}>{busy && <span className="spinner" aria-hidden="true"/>}{busy ? copy.verifyCode : 'Баталгаажуулах'}</button>
      <span className="sr-only" role="status">{busy ? copy.loading : ''}</span>
    </form>
  </main>;

  return <main className="phone auth-screen">
    <section className="auth-hero">
      <Route className="auth-route-art" size={330} strokeWidth={.5} aria-hidden="true"/>
      <Brand light/>
      <h1 className="display">{heading || 'Ачаагаа хэдхэн товшилтоор тээвэрлүүл'}</h1>
    </section>
    <section className="auth-body">
      <div><h2>Утасны дугаараа оруулна уу</h2><p className="muted">{copy.phoneIntro}</p></div>
      <form className="auth-form" onSubmit={e => {e.preventDefault(); void request();}} aria-busy={busy}>
        <label className="field-label" htmlFor="phone">Утасны дугаар</label>
        <div className="phone-field"><span className="phone-prefix">+976</span><input id="phone" className="field" type="tel" inputMode="numeric" autoComplete="tel-national" value={phoneFmt(phone)} disabled={busy} onChange={e => {setPhone(e.target.value.replace(/\D/g,'').slice(0,8)); setError('');}} placeholder="8888 8888" aria-describedby={error ? 'phone-help auth-error' : 'phone-help'} aria-invalid={!!error}/></div>
        <p id="phone-help" className="field-help">{copy.phoneHelp}</p>
        {error && <p id="auth-error" className="error" role="alert">{error}</p>}
        <button className="btn btn-primary" disabled={phone.length !== 8 || busy}>{busy && <span className="spinner" aria-hidden="true"/>}{busy ? copy.requestCode : 'Үргэлжлүүлэх'}</button>
        <span className="sr-only" role="status">{busy ? copy.requestCode : ''}</span>
      </form>
      <p className="auth-terms muted">Үргэлжлүүлснээр та <a href="/terms">үйлчилгээний нөхцөл</a>-ийг зөвшөөрнө.</p>
    </section>
  </main>;
}
