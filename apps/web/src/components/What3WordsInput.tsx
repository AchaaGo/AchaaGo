'use client';
import {useEffect,useRef,useState} from 'react';
import {refreshSession,type Point} from '@/lib/api';
import {cycleHighlight} from '@/lib/googlePlaces';
import {normalizeWords,type WordSuggestion} from '@/lib/what3words';
import {customerCopy as copy} from './customerCopy';

export function What3WordsInput({label,value,onChange,onSelect,onGoogle,disabled}:{
  label:string; value:string; onChange:(value:string)=>void; onSelect:(point:Point)=>Promise<void>; onGoogle:()=>void; disabled:boolean;
}) {
  const [suggestions,setSuggestions] = useState<WordSuggestion[]>([]);
  const [highlight,setHighlight] = useState(-1);
  const [loading,setLoading] = useState(false), [resolving,setResolving] = useState(false), [error,setError] = useState('');
  const generation = useRef(0), active = useRef<AbortController|null>(null);
  const lastSelected = useRef(value);
  const selectedRef = useRef(onSelect); selectedRef.current=onSelect;
  function cancel() {generation.current++;active.current?.abort();active.current=null}
  useEffect(() => () => cancel(),[]);
  async function request(action:'suggest'|'resolve',words:string,controller:AbortController) {
    const timer=setTimeout(()=>controller.abort(),12000);
    try {
      const send=()=>fetch('/address/what3words',{method:'POST',headers:{'Content-Type':'application/json'},credentials:'same-origin',cache:'no-store',body:JSON.stringify({action,words}),signal:controller.signal});
      let response=await send();
      if(response.status===401 && await refreshSession()==='ok' && !controller.signal.aborted)response=await send();
      const body=await response.json();
      if(!response.ok)throw new Error(body.detail||'W3W_UNAVAILABLE');
      return body;
    } finally {clearTimeout(timer)}
  }
  function message(error:unknown) {
    const code=error instanceof Error?error.message:'';
    return code==='W3W_INVALID'?copy.w3wInvalid:code==='W3W_NOT_FOUND'?copy.w3wNotFound:code==='W3W_QUOTA'?copy.w3wQuota:code==='LOGIN_REQUIRED'?copy.w3wLogin:code==='W3W_TIMEOUT'||(error instanceof Error&&error.name==='AbortError')?copy.w3wTimeout:copy.w3wUnavailable;
  }
  useEffect(() => {
    cancel();setSuggestions([]);setHighlight(-1);setError('');setLoading(false);setResolving(false);
    const words=normalizeWords(value), token=generation.current;
    if(!words || disabled || value===lastSelected.current)return;
    const controller=new AbortController();active.current=controller;
    const timer=setTimeout(()=>{
      setLoading(true);
      request('suggest',words,controller).then(body=>{
        if(token===generation.current){setSuggestions(body.suggestions??[]);if(!body.suggestions?.length)setError(copy.w3wNotFound)}
      }).catch(error=>{if(token===generation.current)setError(message(error))}).finally(()=>{if(token===generation.current)setLoading(false)});
    },350);
    return()=>{clearTimeout(timer);cancel()};
  },[value,disabled]);
  async function resolve(value:string) {
    if(disabled || resolving)return;
    const words=normalizeWords(value);
    if(!words){setError(copy.w3wInvalid);return}
    cancel();const token=generation.current,controller=new AbortController();active.current=controller;
    setResolving(true);setLoading(false);setError('');setSuggestions([]);setHighlight(-1);
    try {
      const {point}=await request('resolve',words,controller);
      if(token!==generation.current)return;
      lastSelected.current=point.address;onChange(point.address);
      await selectedRef.current(point);
    } catch(error){if(token===generation.current)setError(message(error))}
    finally{if(token===generation.current)setResolving(false)}
  }
  return <div className="w3w-input">
    <label className="sr-only" htmlFor="w3w-address">{label} — {copy.w3wSearch}</label>
    <div className="destination-field"><span aria-hidden="true">///</span><input autoFocus id="w3w-address" value={value} onChange={event=>onChange(event.target.value)} placeholder={copy.w3wPlaceholder} autoComplete="off" autoCapitalize="none" spellCheck={false} maxLength={150} disabled={disabled} role="combobox" aria-autocomplete="list" aria-expanded={suggestions.length>0} aria-controls={suggestions.length?'w3w-suggestions':undefined} aria-activedescendant={highlight>=0?`w3w-option-${highlight}`:undefined} aria-describedby="w3w-feedback" aria-invalid={!!error} onKeyDown={event=>{
      if(event.key==='Escape'){cancel();setSuggestions([]);setHighlight(-1);setLoading(false);setResolving(false)}
      if((event.key==='ArrowDown'||event.key==='ArrowUp')&&suggestions.length){event.preventDefault();setHighlight(index=>cycleHighlight(index,suggestions.length,event.key==='ArrowDown'?1:-1))}
      if(event.key==='Enter'){event.preventDefault();void resolve(highlight>=0?suggestions[highlight].words:value)}
    }}/><button type="button" className="w3w-resolve" disabled={disabled||resolving||!value.trim()} onClick={()=>void resolve(value)}>{copy.w3wUse}</button></div>
    <p id="w3w-feedback" className={`search-feedback${error?' error':''}`} role="status">{resolving?copy.w3wChecking:loading?copy.searching:error||copy.w3wHelp}</p>
    {suggestions.length>0&&<div id="w3w-suggestions" className="suggest-list" role="listbox" aria-label={copy.w3wSuggestions}>{suggestions.map((item,index)=><button type="button" className="suggest-option" id={`w3w-option-${index}`} key={item.words} role="option" aria-selected={index===highlight} onMouseEnter={()=>setHighlight(index)} onClick={()=>void resolve(item.words)}><span>///{item.words}<small>{[item.nearestPlace,item.country].filter(Boolean).join(' · ')}</small></span></button>)}</div>}
    {error&&<button type="button" className="text-button w3w-back" disabled={disabled} onClick={onGoogle}>{copy.w3wBack}</button>}
  </div>;
}
