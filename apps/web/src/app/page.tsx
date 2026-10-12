'use client';

import {useEffect, useState} from 'react';
import {CustomerFlow} from '@/components/CustomerFlow';
import {PhoneLogin} from '@/components/PhoneLogin';
import {api} from '@/lib/api';

// Phone-first: the login shows at once. A customer still signed in (the 30-day session that
// api() renews) is let straight through instead of being sent, and charged for, a new SMS code.
export default function Page(){
  const [user,setUser]=useState<any>(null);
  useEffect(()=>{api<any>('/auth/me').then(setUser).catch(()=>{})},[]);
  return <div className="shell customer-desktop">{user?<CustomerFlow/>:<PhoneLogin onDone={setUser}/>}</div>;
}
