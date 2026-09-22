'use client';

import {useState} from 'react';
import {CustomerFlow} from '@/components/CustomerFlow';
import {PhoneLogin} from '@/components/PhoneLogin';

export default function Page(){
  const [user,setUser]=useState<any>(null);
  return <div className="shell customer-desktop">{user?<CustomerFlow/>:<PhoneLogin onDone={setUser}/>}</div>;
}
