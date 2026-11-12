import {encodeSnapshot,digest,applyJob} from './bookmarks.mjs';
const bytes = text => new TextEncoder().encode(text);
const base64 = data => btoa(String.fromCharCode(...data));
export async function uploadSnapshot(client, raw) {
  const data=bytes(raw),total=Math.ceil(data.length/32000),transfer=crypto.randomUUID();
  if(data.length>=8000000)throw new Error('snapshot-limit');
  for(let part=0;part<total;part++)await client.send({command:'upload',transfer,part,total,payload:base64(data.slice(part*32000,(part+1)*32000))});
}
export async function runAPI(client, bookmarks, storage, active, changed) {
  async function record(result,command='result'){
    const data=bytes(JSON.stringify(result)),total=Math.ceil(data.length/32000),transfer=crypto.randomUUID();
    if(data.length>=8000000)throw new Error('record-limit');
    for(let part=0;part<total;part++){
      const response=await client.send({command,transfer,part,total,payload:base64(data.slice(part*32000,(part+1)*32000))});
      if(response.stopped){const error=new Error('stopped');error.stopped=true;throw error;}
    }
  }
  await uploadSnapshot(client,encodeSnapshot(await bookmarks.getTree()));
  const handled=new Set();let transfer=null;
  while(active() && client.port && client.session?.expires*1000>Date.now()){
    const response=await client.send({command:'poll'});
    if(response.job){
      const chunk=response.job;
      if(chunk.part===0){if(transfer)throw new Error('overlapping-job');transfer={id:chunk.id,total:chunk.total,next:0,chunks:[],length:0};}
      if(!transfer||transfer.id!==chunk.id||transfer.total!==chunk.total||transfer.next!==chunk.part||chunk.total<1||chunk.total>256)throw new Error('job-chunk');
      const data=Uint8Array.from(atob(chunk.payload),c=>c.charCodeAt(0));transfer.length+=data.length;if(transfer.length>=8000000)throw new Error('job-limit');
      transfer.chunks.push(data);transfer.next++;
      if(transfer.next===transfer.total){
        const joined=new Uint8Array(transfer.length);let offset=0;for(const data of transfer.chunks){joined.set(data,offset);offset+=data.length;}
        const job=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(joined));
        if(typeof job.id!=='string'||job.id.toLowerCase()!==transfer.id||job.sessionID.toLowerCase()!==client.session.sessionID||handled.has(transfer.id))throw new Error('job-identity');
        handled.add(transfer.id);transfer=null;changed('working');
        try{
          let raw;
          if(job.command==='snapshot')raw=encodeSnapshot(await bookmarks.getTree());
          else if(job.command==='adopt'){
            raw=encodeSnapshot(await bookmarks.getTree());if(await digest(raw)!==job.expected)throw new Error('stale-adoption');await storage.remove('inflight');
          }else if(job.command==='apply'){
            if(!response.writable)throw new Error('writes-not-enabled');
            if(response.stopped){const error=new Error('stopped');error.stopped=true;throw error;}
            const pending=await storage.get('inflight');if(pending.inflight)throw new Error('unresolved-interruption');
            const applied=await applyJob(job,bookmarks,storage,record);raw=applied.raw;
            await uploadSnapshot(client,raw);await record(applied.result);changed('ready');continue;
          }else throw new Error('unknown-job');
          await uploadSnapshot(client,raw);await record({jobID:job.id,state:'succeeded'});changed('ready');
        }catch(error){
          // An exception can follow a successful API call. Never replay or automatically roll back.
          try{await uploadSnapshot(client,encodeSnapshot(await bookmarks.getTree()));await record({jobID:job.id,state:error.stopped?'stopped':'uncertain',detail:'Refresh and explicitly adopt Chrome state before another apply.'});}catch{}
          changed('interrupted');
        }
      }
      continue;
    }
    await new Promise(resolve=>setTimeout(resolve,1000));
  }
}
