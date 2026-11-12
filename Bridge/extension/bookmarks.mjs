export function encodeSnapshot(tree) {
  const nodes = [], seen = new Set();
  function visit(node, parent, managed, depth) {
    if (depth > 64 || nodes.length >= 20000 || typeof node.id !== 'string' || !node.id || seen.has(node.id)) throw new Error('snapshot-limit');
    seen.add(node.id);
    const inherited = managed || !!node.unmodifiable;
    nodes.push({id:node.id, parent, title:node.title ?? '', url:node.url ?? null, children:(node.children ?? []).map(n=>n.id), folderType:node.folderType ?? null, syncing:typeof node.syncing === 'boolean' ? node.syncing : null, managed:inherited});
    for (const child of node.children ?? []) visit(child,node.id,inherited,depth+1);
  }
  if (!Array.isArray(tree) || tree.length !== 1) throw new Error('snapshot-root');
  visit(tree[0],null,false,0);
  const text=canonical(nodes); if(new TextEncoder().encode(text).length>=8000000)throw new Error('snapshot-limit');return text;
}
export function canonical(nodes) {
  return JSON.stringify({nodes:[...nodes].sort((a,b)=>a.id<b.id?-1:a.id>b.id?1:0).map(n=>({id:n.id,parent:n.parent ?? null,title:n.title,url:n.url ?? null,children:n.children,folderType:n.folderType ?? null,syncing:n.syncing ?? null,managed:n.managed}))});
}
export async function digest(text) {return [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(text)))].map(n=>n.toString(16).padStart(2,'0')).join('');}
export function desiredTree(job, raw) {
  const nodes=JSON.parse(raw).nodes, live=new Map(nodes.map(n=>[n.id,n])), desired=new Map();
  if(!Array.isArray(job.desired) || job.desired.length<1 || job.desired.length>10000)throw new Error('desired-limit');
  const scope=live.get(job.scope);
  if(!scope || scope.parent===null || scope.url!==null || scope.syncing!==false || scope.managed || (scope.folderType && !['bookmarks-bar','other','mobile'].includes(scope.folderType)))throw new Error('read-only-scope');
  const allowed=new Set();
  function collect(id){if(allowed.has(id))throw new Error('cycle');allowed.add(id);for(const c of live.get(id).children)collect(c);}
  collect(scope.id);
  const recoveries=new Set(job.recoveryIDs);
  for(const id of recoveries){const n=live.get(id);if(!n || n.parent!==scope.id || n.url!==null)throw new Error('changed-recovery');}
  const seenIDs=new Set();let root;
  for(const n of job.desired){
    if(typeof n.key!=='string' || desired.has(n.key) || typeof n.title!=='string' || n.title.length>4096 || !Array.isArray(n.children))throw new Error('desired-node');
    n.url??=null;n.parent??=null;n.id??=null;
    if(n.id){const old=live.get(n.id);if(!allowed.has(n.id) || seenIDs.has(n.id) || old.managed || old.syncing!==false || (old.folderType && n.id!==scope.id) || recoveries.has(n.id) || (old.url===null)!==(n.url===null))throw new Error('protected-node');seenIDs.add(n.id);}
    if(n.url!==null && (!n.id || live.get(n.id).url!==n.url)){const u=new URL(n.url);if(!['http:','https:'].includes(u.protocol)||!u.hostname)throw new Error('url');}
    if(n.parent===null){if(root || n.id!==scope.id || n.title!==scope.title || n.url!==null)throw new Error('protected-root');root=n.key;}
    desired.set(n.key,n);
  }
  if(!root)throw new Error('desired-root');
  const visited=new Set();
  function walk(key,parent,depth){const n=desired.get(key);if(!n || visited.has(key)||depth>64||n.parent!==parent||(n.url!==null&&n.children.length)||new Set(n.children).size!==n.children.length)throw new Error('desired-hierarchy');visited.add(key);for(const c of n.children)walk(c,key,depth+1);}
  walk(root,null,0);if(visited.size!==desired.size)throw new Error('desired-orphans');
  // Every changed or removed descendant must be writable, including inherited managed states.
  for(const id of allowed){if(id===scope.id)continue;const n=live.get(id);if(n.managed || n.syncing!==false || n.folderType)throw new Error('read-only-descendant');}
  return {desired,root,live,allowed,recoveries};
}
export async function applyJob(job, bookmarks, storage, record) {
  let raw=encodeSnapshot(await bookmarks.getTree());
  if(await digest(raw)!==job.expected)throw new Error('stale-before-apply');
  const {desired,root,allowed,recoveries}=desiredTree(job,raw);
  const mapping=Object.assign(Object.create(null),Object.fromEntries([...desired.values()].filter(n=>n.id).map(n=>[n.key,n.id])));
  let sequence=0,recovery=null;
  async function mutate(kind,args,key=null){
    const before=encodeSnapshot(await bookmarks.getTree());if(before!==raw)throw new Error('concurrent-change');
    const intent={jobID:job.id,state:'intent',sequence,recovery,detail:JSON.stringify({kind,args,key})};
    await storage.set({inflight:intent});await record(intent,'progress');
    const answer=await bookmarks[kind](...args);
    const after=encodeSnapshot(await bookmarks.getTree());
    const expected=JSON.parse(before).nodes, indexed=new Map(expected.map(n=>[n.id,n]));
    if(kind==='create'){
      const n=JSON.parse(after).nodes.find(n=>n.id===answer.id);
      if(!n||indexed.has(n.id)||n.parent!==args[0].parentId||n.title!==args[0].title||n.url!==(args[0].url??null)||n.children.length||n.managed||n.syncing!==false)throw new Error('unexpected-create');
      indexed.get(n.parent).children.push(n.id);expected.push(n);
    }else if(kind==='update'){
      const n=indexed.get(args[0]);if('title'in args[1])n.title=args[1].title;if('url'in args[1])n.url=args[1].url;
    }else{
      const n=indexed.get(args[0]),old=indexed.get(n.parent),destination=indexed.get(args[1].parentId);
      old.children=old.children.filter(id=>id!==n.id);n.parent=destination.id;
      destination.children.splice(args[1].index??destination.children.length,0,n.id);
    }
    if(canonical(expected)!==after)throw new Error('unexpected-transition');
    raw=after;
    await record({jobID:job.id,state:'observed',sequence,mapping:key?{[key]:answer.id}:undefined,recovery,detail:kind},'progress');
    sequence++;
    return answer;
  }
  async function place(key){
    const n=desired.get(key);
    if(key!==root){
      const parentId=mapping[n.parent];
      if(!mapping[key]){const created=await mutate('create',[{parentId,title:n.title,...(n.url!==null?{url:n.url}:{})}],key);mapping[key]=created.id;}
      else{
        let current=JSON.parse(raw).nodes.find(x=>x.id===mapping[key]);
        if(current.parent!==parentId)await mutate('move',[current.id,{parentId}]);
        current=JSON.parse(raw).nodes.find(x=>x.id===mapping[key]);
        const changes={};if(current.title!==n.title)changes.title=n.title;if(current.url!==n.url)changes.url=n.url;
        if(Object.keys(changes).length)await mutate('update',[current.id,changes]);
      }
    }
    for(const child of n.children)await place(child);
  }
  await place(root);
  const current=new Map(JSON.parse(raw).nodes.map(n=>[n.id,n]));
  const keep=new Set(Object.values(mapping)), discarded=new Set();
  function protectRecovery(id){discarded.add(id);for(const c of current.get(id).children)protectRecovery(c);}
  for(const id of recoveries)protectRecovery(id);
  const removed=[...allowed].filter(id=>!keep.has(id)&&!discarded.has(id));
  const removedSet=new Set(removed), top=removed.filter(id=>!removedSet.has(current.get(id).parent));
  if(top.length){
    recovery=(await mutate('create',[{parentId:job.scope,title:'Galmuri Recovery '+job.id.slice(0,8)}])).id;
    for(const id of top)await mutate('move',[id,{parentId:recovery}]);
  }
  for(const n of desired.values()){
    for(let i=0;i<n.children.length;i++){
      const parentId=mapping[n.key],id=mapping[n.children[i]],p=JSON.parse(raw).nodes.find(x=>x.id===parentId);
      if(p.children[i]!==id)await mutate('move',[id,{parentId,index:i}]);
    }
  }
  const final=new Map(JSON.parse(raw).nodes.map(n=>[n.id,n])), excluded=new Set([...recoveries,...(recovery?[recovery]:[])]);
  for(const n of desired.values()){
    const actual=final.get(mapping[n.key]);
    if(!actual||actual.title!==n.title||actual.url!==n.url||JSON.stringify(actual.children.filter(id=>!excluded.has(id)))!==JSON.stringify(n.children.map(k=>mapping[k])))throw new Error('final-verification');
  }
  await storage.remove('inflight');
  return {raw,result:{jobID:job.id,state:'succeeded',mapping,recovery,detail:String(sequence)}};
}
