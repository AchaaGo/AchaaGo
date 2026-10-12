import Image from 'next/image';

const brandName = 'AchaaGo';

export function Brand({light=false}:{light?:boolean}) {
  return <div aria-label={brandName} style={{display:'flex',alignItems:'center',gap:8,color:light?'white':'var(--ink)'}}>
    <Image src="/achaago-mark.png" alt="" width={64} height={32} priority style={{width:64,height:32,objectFit:'contain',flexShrink:0}} />
    <strong className="display" style={{fontSize:19,whiteSpace:'nowrap'}}>{brandName.slice(0,5)}<span style={{color:'#007BFF'}}>{brandName.slice(5)}</span></strong>
  </div>;
}
