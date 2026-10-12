import type {Metadata, Viewport} from 'next';
import './globals.css';
import {ThemeToggle} from '@/components/ThemeToggle';

export const metadata: Metadata = {title:'AchaaGo', description:'Улаанбаатар хотын ачаа тээврийн үйлчилгээ', icons:{icon:'/icon.svg'}};
export const viewport: Viewport = {width:'device-width', initialScale:1, viewportFit:'cover', themeColor:'#E84616'};

export default function RootLayout({children}:{children:React.ReactNode}) {
  return <html lang="mn" suppressHydrationWarning><head><script dangerouslySetInnerHTML={{__html:`(function(){var t;try{t=localStorage.getItem('achaago-theme')}catch(e){}if(t!=='light'&&t!=='dark')t=window.matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light';document.documentElement.dataset.theme=t})()`}}/></head><body>{children}<ThemeToggle/></body></html>;
}
