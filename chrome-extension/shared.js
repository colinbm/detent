// Shared by the service worker and the popup.
//
// A rule is { host, account, label, submit }: on `host` and its subdomains, fill in the code
// for the Detent account with id `account` (shown as `label`), then submit the form if `submit`.

const NATIVE_HOST = 'com.colinbm.detent';

/** Asks the `detent` tool. Resolves to its reply, or to { error } if it could not be reached. */
async function askDetent(message) {
  try {
    return await chrome.runtime.sendNativeMessage(NATIVE_HOST, message);
  } catch (error) {
    return { error: error.message, unreachable: true };
  }
}

async function loadRules() {
  const { rules = [] } = await chrome.storage.local.get('rules');
  return rules;
}

/** The host name in something the user typed, which may be a whole URL. Null if there is none. */
function cleanHost(text) {
  text = text.trim().toLowerCase();
  if (!text) return null;
  try {
    const host = new URL(text.includes('://') ? text : `https://${text}`).hostname;
    return host.replace(/^www\./, '') || null;
  } catch {
    return null;
  }
}

function hostMatches(host, ruleHost) {
  return host === ruleHost || host.endsWith(`.${ruleHost}`);
}

/** The rule for `host`. The most specific wins, so a rule for a subdomain beats its parent's. */
function findRule(rules, host) {
  return rules
    .filter((rule) => hostMatches(host, rule.host))
    .sort((a, b) => b.host.length - a.host.length)[0];
}

/** The match pattern covering a rule's host and, where it can have any, its subdomains. */
function originPattern(host) {
  const bare = !host.includes('.') || /^[\d.]+$/.test(host) || host.startsWith('[');
  return bare ? `*://${host}/*` : `*://*.${host}/*`;
}

/**
 * Tells Detent that `host` uses the account with id `account`, so AutoFill can offer its code
 * there. `chosen` is true when the user has just picked the account, which brings the site back
 * if they had removed it in the app.
 */
function rememberSite(host, account, chosen) {
  return askDetent({ cmd: 'remember', id: account, host, chosen });
}
