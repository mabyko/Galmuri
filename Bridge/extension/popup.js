import {runAPI} from './api-client.mjs';
import {ProofClient} from './client.mjs';
import {configuration} from './config.js';
import {copy} from './strings.mjs';
const text = copy(navigator.language);
for (const id of ['title','detail','nameLabel','connect','check','disconnect','help','limit']) document.getElementById(id).textContent = text[id];
document.documentElement.lang = navigator.language;
let apiRunning = false;
const client = new ProofClient(chrome.runtime, chrome.storage.local);
const name = document.getElementById('name'), connect = document.getElementById('connect'), check = document.getElementById('check'), disconnect = document.getElementById('disconnect');
function changed(message) {
  document.getElementById('status').textContent = message ? text[message.status] : text.closed;
  document.getElementById('code').textContent = message?.code ?? '';
  check.disabled = !message || apiRunning; disconnect.disabled = !message; connect.disabled = !!message; name.disabled = !!message;
}
connect.addEventListener('click', async () => {
  connect.disabled = true;
  try { await client.connect(configuration.host, configuration.variant, name.value, changed); }
  catch { changed(null); document.getElementById('status').textContent = text.failed; }
});
check.addEventListener('click', async () => { check.disabled = true; try {
  const result = await client.status();
  if (result.status === 'verified' && !apiRunning) { apiRunning = true; check.disabled = true;
    runAPI(client, chrome.bookmarks, chrome.storage.local, () => !!client.port, state => { document.getElementById('status').textContent = text[state]; }).catch(() => { client.disconnect(); changed(null); }).finally(() => { apiRunning = false; });
  }
} catch { changed(null); } });
disconnect.addEventListener('click', () => { client.disconnect(); changed(null); });
window.addEventListener('pagehide', () => client.disconnect());
changed(null);
