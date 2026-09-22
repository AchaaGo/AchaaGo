import type {Metadata, Viewport} from 'next';
import './globals.css';

export const metadata: Metadata = {title:'AchaaGo', description:'Улаанбаатар хотын ачаа тээврийн үйлчилгээ', icons:{icon:'/icon.svg'}};
export const viewport: Viewport = {width:'device-width', initialScale:1, maximumScale:1, viewportFit:'cover', themeColor:'#14213D'};

export default function RootLayout({children}:{children:React.ReactNode}) {
  return <html lang="mn"><body>{children}</body></html>;
}
