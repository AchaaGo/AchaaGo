import {PublicTracking} from '@/components/PublicTracking';
export default async function TrackingPage({params}:{params:Promise<{token:string}>}){const {token}=await params;return <div className="shell customer-desktop"><PublicTracking token={token}/></div>}
