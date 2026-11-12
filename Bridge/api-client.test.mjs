import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {runAPI} from './extension/api-client.mjs';
import {encodeSnapshot, digest} from './extension/bookmarks.mjs';

function fixture() {
  const sessionID=randomUUID(), installationID=randomUUID(), state={}, sent=[], changes=[];
  const nodes=[{id:'0',title:'',syncing:false,children:[{id:'scope',title:'Scope',syncing:false,children:[{id:'a',title:'A',url:'https://example.test/a',syncing:false}]}]}];
  let current=true, operations=0, response;
  const api={
    getTree:async()=>structuredClone(nodes),
    update:async(id,values)=>{assert.equal(id,'a');operations++;Object.assign(nodes[0].children[0].children[0],values);return structuredClone(nodes[0].children[0].children[0]);},
    create:async()=>{operations++;throw new Error('unexpected-create');},
    move:async()=>{operations++;throw new Error('unexpected-move');}
  };
  const storage={get:async()=>structuredClone(state),set:async value=>Object.assign(state,structuredClone(value)),remove:async key=>{delete state[key];}};
  const client={port:{},session:{sessionID,expires:Date.now()/1000+60},send:async message=>{
    if(!client.port)throw new Error('disconnected');
    sent.push(structuredClone(message));
    if(message.command==='poll'){const answer=response;response=null;assert.ok(answer,'unexpected replay/poll');return answer;}
    if(message.command==='result')current=false;
    return {};
  }};
  const job=async(command='apply')=>({id:randomUUID(),sessionID,installationID,command,scope:'scope',expected:await digest(encodeSnapshot(nodes)),recoveryIDs:[],desired:[
    {key:'root',id:'scope',title:'Scope',url:null,parent:null,children:['a']},
    {key:'a',id:'a',title:'Edited',url:'https://example.test/a',parent:'root',children:[]}
  ]});
  const queue=(value,writable=true)=>{response={writable,job:{id:value.id,total:1,part:0,payload:Buffer.from(JSON.stringify(value)).toString('base64')}};};
  return {client,api,storage,state,sent,nodes,job,queue,stop:()=>{current=false;},count:()=>operations,
    run:()=>runAPI(client,api,storage,()=>current,status=>changes.push(status)),changes};
}
const results=f=>f.sent.filter(x=>x.command==='result').map(x=>JSON.parse(Buffer.from(x.payload,'base64').toString()));

test('expired or cancelled sessions do not poll or mutate',async()=>{
  for(const kind of ['expired','cancelled']){
    const f=fixture();f.queue(await f.job());
    if(kind==='expired')f.client.session.expires=1;else f.stop();
    await f.run();assert.equal(f.count(),0);assert.ok(f.sent.every(x=>x.command==='upload'));
  }
});
test('a reconnect with durable interruption refuses a new apply',async()=>{
  const f=fixture();f.state.inflight={jobID:randomUUID(),state:'intent'};const pending=structuredClone(f.state.inflight);
  f.queue(await f.job());await f.run();
  assert.equal(f.count(),0);assert.deepEqual(f.state.inflight,pending);assert.equal(results(f)[0].state,'uncertain');
});
test('read-only connection rejects apply before a mutation intent',async()=>{
  const f=fixture();f.queue(await f.job(),false);await f.run();
  assert.equal(f.count(),0);assert.equal(f.state.inflight,undefined);assert.equal(results(f)[0].state,'uncertain');
});
test('disconnect after a successful call retains intent without replay',async()=>{
  const f=fixture(),update=f.api.update;
  f.api.update=async(...args)=>{const answer=await update(...args);f.client.port=null;return answer;};
  f.queue(await f.job());await f.run();
  assert.equal(f.count(),1);assert.equal(f.nodes[0].children[0].children[0].title,'Edited');
  assert.equal(f.state.inflight.state,'intent');assert.equal(results(f).length,0);assert.ok(f.changes.includes('interrupted'));
});
test('host denial of intent acknowledgement prevents the API call',async()=>{
  const f=fixture(),send=f.client.send;
  f.client.send=async message=>{if(message.command==='progress')throw new Error('owner exited or session expired');return send(message);};
  f.queue(await f.job());await f.run();
  assert.equal(f.count(),0);assert.equal(f.state.inflight.state,'intent');assert.equal(results(f)[0].state,'uncertain');
});
test('adoption needs the reviewed fingerprint and never writes bookmarks',async()=>{
  for(const changed of [false,true]){
    const f=fixture();f.state.inflight={jobID:randomUUID(),state:'intent'};
    const job=await f.job('adopt');if(changed)job.expected='0'.repeat(64);
    f.queue(job);await f.run();assert.equal(f.count(),0);
    assert.equal(results(f)[0].state,changed?'uncertain':'succeeded');assert.equal(!!f.state.inflight,changed);
  }
});
test('foreign-session job identities reject outside apply',async()=>{
  const f=fixture(),job=await f.job();job.sessionID=randomUUID();f.queue(job);
  await assert.rejects(f.run(),/job-identity/);assert.equal(f.count(),0);assert.equal(f.state.inflight,undefined);
});
test('an acknowledged stop prevents the next mutation and retains interruption',async()=>{
  const f=fixture(),send=f.client.send;
  f.client.send=async message=>message.command==='progress'?{stopped:true}:send(message);
  f.queue(await f.job());await f.run();
  assert.equal(f.count(),0);assert.equal(f.state.inflight.state,'intent');assert.equal(results(f)[0].state,'stopped');
});
test('large result is chunked while 300 creates use compact durable progress',async()=>{
  const f=fixture(),folder=f.nodes[0].children[0],root=randomUUID();
  folder.children=Array.from({length:600},(_,i)=>({id:'n'+i,title:'Item '+i,url:'https://example.test/'+i,syncing:false}));
  const existing=folder.children.map(n=>({key:randomUUID(),id:n.id,title:n.title,url:n.url,parent:root,children:[]}));
  const additions=Array.from({length:300},(_,i)=>({key:randomUUID(),id:null,title:'New '+i,url:'https://example.test/new/'+i,parent:root,children:[]}));
  let created=0;
  f.api.create=async values=>{const n={id:'created-'+(++created),title:values.title,url:values.url,syncing:false};folder.children.push(n);return structuredClone(n);};
  const job=await f.job();job.expected=await digest(encodeSnapshot(f.nodes));
  job.desired=[{key:root,id:'scope',title:folder.title,url:null,parent:null,children:[...existing,...additions].map(n=>n.key)},...existing,...additions];
  f.queue(job);await f.run();assert.equal(created,300);assert.equal(f.state.inflight,undefined);
  const chunks=f.sent.filter(x=>x.command==='result');assert.ok(chunks.length>1);
  const result=JSON.parse(Buffer.concat(chunks.map((chunk,index)=>{assert.equal(chunk.part,index);assert.equal(chunk.total,chunks.length);return Buffer.from(chunk.payload,'base64');})).toString());
  assert.equal(result.state,'succeeded');assert.equal(Object.keys(result.mapping).length,901);
  const progress=f.sent.filter(x=>x.command==='progress');assert.equal(progress.length,600);
  assert.ok(progress.every(x=>Buffer.from(x.payload,'base64').length<1000));
  assert.ok(f.sent.every(x=>!x.payload||Buffer.from(x.payload,'base64').length<=32000));
});
