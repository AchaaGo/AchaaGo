'use client';
import {useEffect, useId, useRef, useState, type CSSProperties, type ReactNode} from 'react';
import {ChevronDown, ChevronUp} from 'lucide-react';
import {customerCopy as copy} from './customerCopy';

/** A non-modal mobile sheet: the exposed map stays interactive. */
export function MapSheet({children, labelledBy, className = ''}:{children:ReactNode; labelledBy?:string; className?:string}) {
  const sheet = useRef<HTMLElement>(null);
  const handle = useRef<HTMLButtonElement>(null);
  const content = useRef<HTMLDivElement>(null);
  const id = useId();
  const [mobile, setMobile] = useState(false);
  const [collapsed, setCollapsed] = useState(false);
  const [offset, setOffset] = useState(0);
  const [dragging, setDragging] = useState(false);
  const limit = useRef(0);
  const gesture = useRef<{y:number; x:number; start:number; moved:boolean} | null>(null);
  const suppressClick = useRef(false);
  const state = useRef({collapsed, mobile});
  state.current = {collapsed, mobile};

  const settle = (next:boolean) => {
    if (next && content.current?.contains(document.activeElement)) handle.current?.focus({preventScroll:true});
    setCollapsed(next); setOffset(next ? limit.current : 0); setDragging(false);
  };
  useEffect(() => {
    const node = sheet.current!;
    const parent = node.parentElement!;
    const query = matchMedia('(max-width:767px)');
    const measure = () => {
      const header = parent.querySelector<HTMLElement>(':scope > .route-search');
      node.style.setProperty('--sheet-header-height', `${header?.offsetHeight ?? 0}px`);
      limit.current = Math.max(0, node.offsetHeight - (handle.current?.offsetHeight ?? 56));
      setOffset(state.current.collapsed && query.matches ? limit.current : 0);
    };
    const change = () => { setMobile(query.matches); measure(); };
    const observer = new ResizeObserver(measure);
    observer.observe(node); observer.observe(parent);
    const header = parent.querySelector('.route-search'); if (header) observer.observe(header);
    query.addEventListener('change', change); change();
    return () => { observer.disconnect(); query.removeEventListener('change', change); };
  }, []);

  // Only take over a downward pull when the content has reached its top.
  // Native scrolling continues for long forms and gestures starting on controls.
  useEffect(() => {
    const node = content.current!;
    const start = (event:TouchEvent) => {
      if (!state.current.mobile || node.scrollTop > 0 || event.touches.length !== 1) return;
      if ((event.target as Element).closest('button,a,input,select,textarea,label')) return;
      const touch = event.touches[0];
      gesture.current = {y:touch.clientY, x:touch.clientX, start:0, moved:false};
    };
    const move = (event:TouchEvent) => {
      const drag = gesture.current;
      if (!drag || event.touches.length !== 1) return;
      const dy = event.touches[0].clientY - drag.y;
      const dx = event.touches[0].clientX - drag.x;
      if (!drag.moved && (dy < -6 || Math.abs(dx) > Math.max(8, Math.abs(dy)))) { gesture.current = null; return; }
      if (dy > 8 && event.cancelable) {
        event.preventDefault(); drag.moved = true; setDragging(true);
        setOffset(Math.min(limit.current, Math.max(0, dy)));
      }
    };
    const end = (event:TouchEvent) => {
      const drag = gesture.current; gesture.current = null;
      if (drag?.moved) settle(event.type !== 'touchcancel' && event.changedTouches[0].clientY - drag.y > 60);
    };
    node.addEventListener('touchstart', start, {passive:true});
    node.addEventListener('touchmove', move, {passive:false});
    node.addEventListener('touchend', end); node.addEventListener('touchcancel', end);
    return () => {
      node.removeEventListener('touchstart', start); node.removeEventListener('touchmove', move);
      node.removeEventListener('touchend', end); node.removeEventListener('touchcancel', end);
    };
  }, []);

  return <section ref={sheet} className={`sheet map-sheet ${className}`} aria-labelledby={collapsed && mobile ? undefined : labelledBy}
    data-collapsed={collapsed && mobile} data-dragging={dragging}
    style={{'--sheet-offset':`${offset}px`} as CSSProperties}>
    <button ref={handle} type="button" className="map-sheet-handle" aria-expanded={!collapsed} aria-controls={id}
      aria-label={collapsed ? copy.expandMapSheet : copy.collapseMapSheet}
      onPointerDown={event => {
        if (!mobile || !event.isPrimary || event.button !== 0) return;
        suppressClick.current = false;
        gesture.current = {y:event.clientY, x:event.clientX, start:collapsed ? limit.current : 0, moved:false};
        event.currentTarget.setPointerCapture(event.pointerId);
      }}
      onPointerMove={event => {
        const drag = gesture.current; if (!drag) return;
        const delta = event.clientY - drag.y;
        if (Math.abs(delta) > 6) { drag.moved = true; setDragging(true); }
        if (drag.moved) setOffset(Math.max(0, Math.min(limit.current, drag.start + delta)));
      }}
      onPointerUp={event => {
        const drag = gesture.current; gesture.current = null; if (!drag) return;
        suppressClick.current = drag.moved;
        if (drag.moved) {
          const delta = event.clientY - drag.y;
          settle(Math.abs(delta) > 40 ? delta > 0 : collapsed);
        }
      }}
      onPointerCancel={() => {gesture.current = null; suppressClick.current = true; settle(collapsed);}}
      onClick={() => {if (suppressClick.current) {suppressClick.current = false; return;} settle(!collapsed);}}
      onKeyDown={event => {
        if (event.key === 'Enter' || event.key === ' ') suppressClick.current = false;
        if (['ArrowDown','ArrowUp','Escape'].includes(event.key)) {
          event.preventDefault(); settle(event.key !== 'ArrowUp');
        }
      }}>
      <span className="map-sheet-grip" aria-hidden="true"/>
      <span className="map-sheet-caption">{collapsed ? copy.expandMapSheet : copy.collapseMapSheet}</span>
      {collapsed ? <ChevronUp size={18} aria-hidden="true"/> : <ChevronDown size={18} aria-hidden="true"/>}
    </button>
    <div ref={content} id={id} className="map-sheet-content" inert={mobile && collapsed}>{children}</div>
  </section>;
}
