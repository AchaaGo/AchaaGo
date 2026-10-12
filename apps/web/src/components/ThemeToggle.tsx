'use client';
import {useEffect, useState} from 'react';
import {createPortal} from 'react-dom';
import {Moon, Sun} from 'lucide-react';
import {customerCopy as copy} from './customerCopy';

const key = 'achaago-theme';
type Theme = 'light' | 'dark';
const savedTheme = (): Theme | null => {
  try { const value = localStorage.getItem(key); return value === 'light' || value === 'dark' ? value : null; }
  catch { return null; }
};

export function ThemeToggle() {
  const [host, setHost] = useState<Element | null>(null);
  useEffect(() => {
    const locate = () => setHost(document.querySelector('.route-screen .map-stage, .admin-shell .sidebar'));
    const observer = new MutationObserver(locate);
    locate(); observer.observe(document.body, {childList:true, subtree:true});
    return () => observer.disconnect();
  }, []);
  const [theme, setTheme] = useState<Theme | null>(null);
  useEffect(() => {
    const root = document.documentElement;
    const system = matchMedia('(prefers-color-scheme: dark)');
    let manual = savedTheme();
    const apply = (value: Theme) => { root.dataset.theme = value; setTheme(value); };
    apply(manual ?? (system.matches ? 'dark' : 'light'));
    const onSystem = () => { if (!manual) apply(system.matches ? 'dark' : 'light'); };
    const onStorage = (event: StorageEvent) => {
      if (event.key !== key && event.key !== null) return;
      manual = savedTheme(); onSystem(); if (manual) apply(manual);
    };
    const onChoice = () => { manual = root.dataset.theme as Theme; setTheme(manual); };
    system.addEventListener('change', onSystem);
    window.addEventListener('storage', onStorage);
    window.addEventListener('achaago-theme-change', onChoice);
    return () => {
      system.removeEventListener('change', onSystem);
      window.removeEventListener('storage', onStorage);
      window.removeEventListener('achaago-theme-change', onChoice);
    };
  }, []);
  const toggle = () => {
    const root = document.documentElement;
    const next = root.dataset.theme === 'dark' ? 'light' : 'dark';
    root.classList.add('theme-switching');
    root.dataset.theme = next;
    setTheme(next);
    try { localStorage.setItem(key, next); } catch { /* Still switch when storage is unavailable. */ }
    window.dispatchEvent(new Event('achaago-theme-change'));
    window.setTimeout(() => root.classList.remove('theme-switching'), 200);
  };
  const label = theme === 'dark' ? copy.switchLight : theme === 'light' ? copy.switchDark : copy.switchTheme;
  const button = <button type="button" className="theme-toggle" onClick={toggle} aria-label={label} title={label}>
    <Sun className="theme-sun" size={21} aria-hidden="true"/>
    <Moon className="theme-moon" size={21} aria-hidden="true"/>
  </button>;
  return host ? createPortal(button, host) : button;
}
