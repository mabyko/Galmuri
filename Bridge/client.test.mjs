import test from 'node:test';
import assert from 'node:assert/strict';
import {ProofClient} from './extension/client.mjs';
import {copy} from './extension/strings.mjs';
import {randomUUID} from 'node:crypto';
function fixture() {
  const callbacks = {}, port = {onMessage: {addListener: f => callbacks.message = f}, onDisconnect: {addListener: f => callbacks.disconnect = f}, disconnect() {this.closed = true;}, postMessage(message) {this.sent = message;}};
  const state = {};
  const client = new ProofClient({connectNative: () => port}, {get: async () => state, set: async x => Object.assign(state, x)}, randomUUID);
  const response = status => ({version:1, variant:'debug', bookmarkAccess:true, apiProtocol:2, requestID:port.sent.requestID, sessionID:'00000000-0000-4000-8000-000000000001', code:'123456', name:'QA', expires:Date.now()/1000+100, status});
  return {client, port, callbacks, state, response};
}
test('explicit pairing, profile-local identity, approval acknowledgement and disconnect', async () => {
  const f = fixture();
  const connection = f.client.connect('host', 'debug', 'QA', () => {});
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.port.sent.command, 'hello');
  assert.equal(f.port.sent.installationID, f.state.installationID);
  f.callbacks.message(f.response('pending')); await connection;
  const check = f.client.status();
  f.callbacks.message(f.response('approved'));
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.port.sent.command, 'acknowledge');
  f.callbacks.message(f.response('verified')); assert.equal((await check).status, 'verified');
  f.client.disconnect(); assert.equal(f.port.closed, true);
});
test('wrong variant, unrequested message, expired reply and bookmark access fail closed', async () => {
  for (const patch of [{apiProtocol:1}, {variant:'release'}, {requestID:randomUUID()}, {expires:1}, {bookmarkAccess:false}, {name:'Wrong profile'}, {sessionID:'-'.repeat(36)}]) {
    const f=fixture(); const result=f.client.connect('host','debug','QA',()=>{});
    const rejected=assert.rejects(result); await new Promise(resolve=>setImmediate(resolve));
    f.callbacks.message({...f.response('pending'),...patch}); await rejected;
    assert.equal(f.client.port,null);
  }
});
test('disconnect rejects pending calls without retries', async () => {
  const f=fixture(); const result=f.client.connect('host','debug','QA',()=>{});
  const rejected=assert.rejects(result); await new Promise(resolve=>setImmediate(resolve));
  const first=f.port.sent.requestID; f.callbacks.disconnect(); await rejected;
  assert.equal(f.port.sent.requestID,first); assert.equal(f.client.port,null);
});
test('invalid names do not open a port and locale copies retain all keys', async () => {
  for(const name of ['', ' ', 'a'.repeat(81), 'QA\nname']) {
    const f=fixture(); await assert.rejects(f.client.connect('host','debug',name,()=>{})); assert.equal(f.port.sent,undefined);
  }
  const keys=Object.keys(copy('en')).sort();
  for(const lang of ['ko-KR','ja-JP','zh-CN','fr-FR']) {
    assert.deepEqual(Object.keys(copy(lang)).sort(),keys);
    assert.ok(Object.values(copy(lang)).every(x=>typeof x==='string' && x.length>0));
  }
});
