import {copy} from "./strings.mjs";
const button = document.getElementById("launch"); button.textContent = copy(navigator.language).launch;
button.addEventListener("click", async () => { try { await chrome.runtime.openOptionsPage(); window.close(); } catch { button.disabled = true; } });
