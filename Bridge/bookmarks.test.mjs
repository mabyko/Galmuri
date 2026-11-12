import test from 'node:test';
import assert from 'node:assert/strict';
import {encodeSnapshot,digest,applyJob,desiredTree} from './extension/bookmarks.mjs';
function fixture(){
 let nodes=[{id:'root',parent:null,title:'',url:null,children:['bar'],folderType:null,syncing:false,managed:false},{id:'bar',parent:'root',title:'Bookmarks bar',url:null,children:['a','b','folder'],folderType:'bookmarks-bar',syncing:false,managed:false},{id:'a',parent:'bar',title:'A',url:'https://example.test/shared',children:[],syncing:false,managed:false},{id:'b',parent:'bar',title:'B',url:'https://example.test/shared',children:[],syncing:false,managed:false},{id:'folder',parent:'bar',title:'Folder',url:null,children:[],syncing:false,managed:false}];
 const clone=x=>JSON.parse(JSON.stringify(x));let count=0;const state={};let hook=null;
 function nested(id){const n=nodes.find(x=>x.id===id);return {...clone(n),children:n.url===null?n.children.map(nested):undefined};}
 const api={getTree:async()=>[nested('root')],create:async args=>{count++;const n={id:'new'+count,parent:args.parentId,title:args.title,url:args.url??null,children:[],syncing:false,managed:false};nodes.find(x=>x.id===n.parent).children.push(n.id);nodes.push(n);return clone(n);},update:async(id,args)=>{count++;Object.assign(nodes.find(n=>n.id===id),args);if(hook)hook(nodes);return clone(nodes.find(n=>n.id===id));},move:async(id,args)=>{count++;const n=nodes.find(x=>x.id===id);nodes.find(x=>x.id===n.parent).children=nodes.find(x=>x.id===n.parent).children.filter(x=>x!==id);n.parent=args.parentId;const parent=nodes.find(x=>x.id===n.parent);parent.children.splice(args.index??parent.children.length,0,id);return clone(n);}};
 const storage={set:async x=>Object.assign(state,x),get:async()=>state,remove:async k=>delete state[k]};
 async function job(){const raw=encodeSnapshot(await api.getTree());return {id:'00000000-0000-4000-8000-000000000001',scope:'bar',expected:await digest(raw),recoveryIDs:[],desired:[{key:'bar',id:'bar',parent:null,title:'Bookmarks bar',url:null,children:['a','b','folder']},{key:'a',id:'a',parent:'bar',title:'A',url:'https://example.test/shared',children:[]},{key:'b',id:'b',parent:'bar',title:'B',url:'https://example.test/shared',children:[]},{key:'folder',id:'folder',parent:'bar',title:'Folder',url:null,children:[]}]};}
 return {api,storage,state,job,nodes,hook:f=>hook=f,count:()=>count};
}
test('create, rename, move, order and duplicate URLs preserve existing IDs',async()=>{
 const f=fixture(),job=await f.job();job.desired[0].children=['folder','a'];job.desired[3].children=['b','new'];job.desired[2].parent='folder';job.desired[1].title='Renamed';job.desired.push({key:'new',id:null,parent:'folder',title:'New',url:'https://example.test/new',children:[]});
 const applied=await applyJob(job,f.api,f.storage,async()=>{});assert.equal(applied.result.state,'succeeded');assert.equal(applied.result.mapping.a,'a');assert.equal(applied.result.mapping.b,'b');assert.ok(applied.result.mapping.new);assert.equal(f.state.inflight,undefined);
});
test('deletion moves originals to recovery; restoring moves the same IDs back',async()=>{
 const f=fixture(),before=await f.job(),job=await f.job();job.desired=job.desired.filter(n=>n.key!=='a');job.desired[0].children=['b','folder'];
 const deleted=await applyJob(job,f.api,f.storage,async()=>{});assert.ok(deleted.result.recovery);assert.equal(f.nodes.find(n=>n.id==='a').parent,deleted.result.recovery);
 before.expected=await digest(deleted.raw);before.recoveryIDs=[deleted.result.recovery];const restored=await applyJob(before,f.api,f.storage,async()=>{});assert.equal(f.nodes.find(n=>n.id==='a').parent,'bar');assert.equal(restored.result.mapping.a,'a');
});
test('stale or read-only scopes reject before the first write',async()=>{
 for(const kind of ['stale','account','managed','root','missing-id']){
  const f=fixture(),job=await f.job();if(kind==='stale')job.expected='wrong';if(kind==='account')f.nodes[1].syncing=true;if(kind==='managed')f.nodes[2].unmodifiable='managed';if(kind==='root')job.scope='root';if(kind==='missing-id')job.desired[1].id='missing';
  await assert.rejects(applyJob(job,f.api,f.storage,async()=>{}));assert.equal(f.count(),0);
 }
});
test('cycles and duplicate desired IDs are rejected',async()=>{
 for(const kind of ['cycle','duplicate']){const f=fixture(),job=await f.job();if(kind==='cycle')job.desired[3].children=['folder'];else job.desired[2].id='a';await assert.rejects(applyJob(job,f.api,f.storage,async()=>{}));assert.equal(f.count(),0);}
});
test('an external change during a write stops the batch with durable intent',async()=>{
 const f=fixture(),job=await f.job();job.desired[1].title='Changed';f.hook(nodes=>{nodes.find(n=>n.id==='b').title='External';});
 await assert.rejects(applyJob(job,f.api,f.storage,async()=>{}));assert.equal(f.nodes.find(n=>n.id==='b').title,'External');assert.equal(f.state.inflight.state,'intent');assert.equal(f.count(),1);
});
test('failure to persist intent prevents API mutation',async()=>{
 const f=fixture(),job=await f.job();job.desired[1].title='Changed';f.storage.set=async()=>{throw new Error('disk full');};await assert.rejects(applyJob(job,f.api,f.storage,async()=>{}));assert.equal(f.count(),0);
});
test('API response loss never causes an automatic mutation retry',async()=>{
 const f=fixture(),job=await f.job();job.desired[1].title='Changed';const update=f.api.update;f.api.update=async(...args)=>{await update(...args);throw new Error('lost reply');};
 await assert.rejects(applyJob(job,f.api,f.storage,async()=>{}));assert.equal(f.count(),1);assert.equal(f.state.inflight.state,'intent');
});
test('snapshot rejects repeated IDs and excessive depth',()=>{
 assert.throws(()=>encodeSnapshot([{id:'x',children:[{id:'x'}]}]));let root={id:'0',children:[]},n=root;for(let i=1;i<70;i++){n.children=[{id:String(i),children:[]}];n=n.children[0];}assert.throws(()=>encodeSnapshot([root]));
});
test('multi-chunk snapshot transport preserves mixed-script UTF-8 bytes',async()=>{
 const {uploadSnapshot}=await import('./extension/api-client.mjs');const calls=[];
 const raw=JSON.stringify({nodes:[{title:'갈무리 · 日本語 · 中文 · 😀'.repeat(8000)}]});
 await uploadSnapshot({send:async chunk=>{calls.push(chunk);}},raw);
 assert.ok(calls.length>1);assert.equal(calls[0].total,calls.length);
 const restored=Buffer.concat(calls.map((c,i)=>{assert.equal(c.part,i);return Buffer.from(c.payload,'base64');})).toString('utf8');
 assert.equal(restored,raw);
});
