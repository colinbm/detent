importScripts('shared.js');

// The content script runs only on the sites that have a rule, so it is registered here
// rather than in the manifest, and re-registered whenever the rules change.
let syncing = Promise.resolve();
function syncContentScript() {
  syncing = syncing.then(async () => {
    const matches = [...new Set((await loadRules()).map((rule) => originPattern(rule.host)))];
    await chrome.scripting.unregisterContentScripts({ ids: ['fill'] }).catch(() => {});
    if (matches.length) {
      await chrome.scripting.registerContentScripts([{ id: 'fill', js: ['content.js'], matches }]);
    }
  }).catch((error) => console.error('Detent:', error));
  return syncing;
}

// Rules made before Detent stored sites with accounts, or while it could not be reached.
async function rememberSites() {
  for (const rule of await loadRules()) await rememberSite(rule.host, rule.account, false);
}

chrome.runtime.onInstalled.addListener(() => {
  syncContentScript();
  rememberSites();
});
chrome.runtime.onStartup.addListener(() => {
  syncContentScript();
  rememberSites();
});
chrome.storage.onChanged.addListener((changes) => {
  if (changes.rules) syncContentScript();
});

// A site has just been allowed: start on its open tabs without waiting for a reload.
chrome.permissions.onAdded.addListener(async ({ origins = [] }) => {
  await syncContentScript();
  if (!origins.length) return;
  for (const tab of await chrome.tabs.query({ url: origins })) {
    chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ['content.js'] }).catch(() => {});
  }
});

// The content script asks for a code when it finds a field to put one in. Which account it
// gets is decided here, from the address Chrome reports for the page, never by the page.
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (message?.type !== 'code' || !sender.tab || sender.frameId !== 0) return;
  codeFor(sender.tab).then(respond);
  return true;
});

async function codeFor(tab) {
  const rule = findRule(await loadRules(), new URL(tab.url).hostname);
  if (!rule) return {};

  const reply = await askDetent({ cmd: 'code', id: rule.account });
  if (reply.error) {
    // Nothing on the page says why no code appeared, so flag it on the toolbar button.
    chrome.action.setBadgeText({ tabId: tab.id, text: '!' });
    chrome.action.setBadgeBackgroundColor({ tabId: tab.id, color: '#d33' });
    chrome.action.setTitle({ tabId: tab.id, title: `Detent: ${reply.error}` });
    return {};
  }
  return { code: reply.code, remaining: reply.remaining, submit: rule.submit };
}
