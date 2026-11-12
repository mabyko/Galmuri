const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u;
export class ProofClient {
  constructor(runtime, storage, uuid = () => crypto.randomUUID()) {
    this.runtime = runtime; this.storage = storage; this.uuid = uuid;
    this.port = null; this.pending = new Map(); this.session = null;
  }
  async connect(host, variant, name, changed) {
    this.disconnect();
    if (typeof name !== 'string' || !name.trim() || name.trim().length > 80 || /[\x00-\x1f\x7f]/u.test(name)) throw new Error('label');
    const saved = await this.storage.get('installationID');
    const installationID = saved.installationID ?? this.uuid();
    if (!UUID.test(installationID)) throw new Error('identity');
    await this.storage.set({installationID});
    const port = this.runtime.connectNative(host);
    this.port = port; this.variant = variant; this.changed = changed;
    port.onMessage.addListener(message => {
      if (port !== this.port) return;
      const request = this.pending.get(message?.requestID);
      if (!request || message.version !== 1 || message.variant !== variant || message.bookmarkAccess !== true || message.apiProtocol !== 2 ||
          !['pending', 'approved', 'verified'].includes(message.status) || !/^[0-9]{6}$/u.test(message.code) ||
          typeof message.sessionID !== 'string' || !UUID.test(message.sessionID) || (this.session && message.sessionID !== this.session.sessionID) ||
          message.name !== name.trim() || !Number.isFinite(message.expires) || message.expires * 1000 <= Date.now() || message.expires * 1000 > Date.now() + 301000) {
        this.disconnect(); changed(null); return;
      }
      clearTimeout(request.timer); this.pending.delete(message.requestID);
      this.session = message; request.resolve(message); changed(message);
    });
    port.onDisconnect.addListener(() => {
      if (port !== this.port) return;
      void this.runtime.lastError;
      this.disconnect(); changed(null);
    });
    return this.send({command: 'hello', apiProtocol: 2, installationID, name: name.trim()});
  }
  send(payload) {
    if (!this.port) return Promise.reject(new Error('disconnected'));
    if (this.pending.size) return Promise.reject(new Error('busy'));
    const requestID = this.uuid();
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.disconnect(); this.changed?.(null); }, 5000);
      this.pending.set(requestID, {resolve, reject, timer});
      try { this.port.postMessage({version: 1, requestID, ...payload}); }
      catch { this.disconnect(); this.changed?.(null); }
    });
  }
  async status() {
    const result = await this.send({command: 'status'});
    return result.status === 'approved' ? this.send({command: 'acknowledge'}) : result;
  }
  disconnect() {
    const port = this.port; this.port = null; this.session = null;
    for (const request of this.pending.values()) { clearTimeout(request.timer); request.reject(new Error('disconnected')); }
    this.pending.clear(); port?.disconnect();
  }
}
