const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const ts=require('typescript');
const source=fs.readFileSync(path.join(__dirname,'../src/lib/roadRoute.ts'),'utf8');
const moduleRef={exports:{}};
vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,{module:moduleRef,exports:moduleRef.exports});
const {decodeRoutePath,roadRoute}=moduleRef.exports;
const encoded='_p~iF~ps|U_ulLnnqC_mqNvxq`@';
const literal=value=>JSON.parse(JSON.stringify(value));
test('decodes the standard Google polyline, including all intermediate points',()=>{
 assert.deepEqual(literal(decodeRoutePath(encoded)),[{lat:38.5,lng:-120.2},{lat:40.7,lng:-120.95},{lat:43.252,lng:-126.453}]);
});
test('rejects truncated, empty and invalid routes without fabricating a line',()=>{
 for(const value of ['', '_', '??', '\u0000', '~~~~~~~~~~~~'])assert.throws(()=>decodeRoutePath(value));
});
test('uses the quote/order geometry without a second routing request',async()=>{
 const result=await roadRoute({importLibrary(){throw Error('Must not request')}},{lat:38.5,lng:-120.2},{lat:43.252,lng:-126.453},encoded);
 assert.equal(result.length,3);
});
test('requests high-quality driving geometry when the backend has no polyline',async()=>{
 const origin={lat:47.9,lng:106.9},destination={lat:47.93,lng:106.92};let request;
 const result=await roadRoute({importLibrary:async name=>{assert.equal(name,'routes');return{Route:{computeRoutes:async value=>{request=value;return{routes:[{path:[origin,{lat:47.9,lng:106.92},destination]}]}}}}}},origin,destination);
 assert.equal(request.travelMode,'DRIVING');assert.equal(request.polylineQuality,'HIGH_QUALITY');assert.deepEqual(literal(request.fields),['path']);assert.equal(result.length,3);
});
test('routing failures are surfaced instead of replaced with endpoint geometry',async()=>{
 const maps={importLibrary:async()=>({Route:{computeRoutes:async()=>({routes:[]})}})};
 await assert.rejects(roadRoute(maps,{lat:47.9,lng:106.9},{lat:47.92,lng:106.91}));
});
