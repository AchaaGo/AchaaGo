const {test}=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),ts=require('typescript');
const React=require('react'),{renderToStaticMarkup}=require('react-dom/server');
function compile(file,customRequire=require){const moduleRef={exports:{}};const source=fs.readFileSync(path.join(__dirname,'../src/components',file),'utf8');vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX,target:ts.ScriptTarget.ES2020}}).outputText,{exports:moduleRef.exports,module:moduleRef,require:customRequire});return moduleRef.exports}
const copy=compile('customerCopy.ts');
const {CustomerPanel}=compile('CustomerPanel.tsx',name=>name==='./customerCopy'?copy:name==='@/lib/api'?{api(){throw Error('No network during render')},phoneFmt:value=>value,ApiError:Error}:require(name));
function render(hasActiveOrder){return renderToStaticMarkup(React.createElement(CustomerPanel,{kind:'menu',customer:null,hasActiveOrder,onClose(){}}))}
test('existing active order state adds a visible and accessible badge without enabling unavailable history',()=>{
 const html=render(true);assert.match(html,/customer-order-dot/);assert.match(html,/Идэвхтэй захиалгатай/);assert.match(html,/<button[^>]*disabled=""[^>]*>.*?Миний захиалгууд/s);
});
test('no active order state produces no badge',()=>{assert.doesNotMatch(render(false),/customer-order-dot|Идэвхтэй захиалгатай/)});
