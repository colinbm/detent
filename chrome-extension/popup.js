const $ = (id) => document.getElementById(id);

function element(tag, text, properties = {}) {
  return Object.assign(document.createElement(tag), { textContent: text }, properties);
}

function showProblem(...parts) {
  $('problem').replaceChildren(...parts);
  $('problem').hidden = false;
}

const hasAccess = (host) => chrome.permissions.contains({ origins: [originPattern(host)] });
// Chrome can close the popup while it asks, so nothing may depend on code running after this.
// The service worker picks up from the grant.
const requestAccess = (host) => chrome.permissions.request({ origins: [originPattern(host)] });

async function saveRules(rules) {
  rules.sort((a, b) => a.host.localeCompare(b.host));
  await chrome.storage.local.set({ rules });
}

async function removeRule(host) {
  const rules = (await loadRules()).filter((rule) => rule.host !== host);
  await saveRules(rules);
  const pattern = originPattern(host);
  if (!rules.some((rule) => originPattern(rule.host) === pattern)) {
    await chrome.permissions.remove({ origins: [pattern] }).catch(() => {});
  }
  showRules();
}

async function showRules() {
  const rules = await loadRules();
  $('sites').hidden = rules.length === 0;

  const rows = await Promise.all(rules.map(async (rule) => {
    const text = element('div');
    text.append(element('span', rule.host), element('span', rule.label + (rule.submit ? ', then submit' : '')));
    const row = element('li');
    row.append(text);
    if (!(await hasAccess(rule.host))) {
      row.append(element('button', 'Allow', {
        className: 'quiet',
        type: 'button',
        title: `Let Detent fill codes on ${rule.host}`,
        onclick: () => requestAccess(rule.host).then(showRules),
      }));
    }
    row.append(element('button', 'Remove', { className: 'quiet', type: 'button', onclick: () => removeRule(rule.host) }));
    return row;
  }));
  $('rules').replaceChildren(...rows);
}

async function showAccounts() {
  const reply = await askDetent({ cmd: 'list' });
  if (reply.unreachable) {
    showProblem('Chrome cannot reach Detent. Run ', element('code', 'detent chrome-setup'),
      ` in a terminal, then open this again. (${reply.error})`);
  } else if (reply.error) {
    showProblem(reply.error);
  } else if (reply.accounts.length === 0) {
    showProblem('Detent has no accounts yet. Add one in the app.');
  }
  const accounts = reply.accounts ?? [];
  $('account').replaceChildren(...accounts.map((account) => new Option(account.label, account.id)));
  $('save').disabled = accounts.length === 0;
  return accounts;
}

/** Fills the form in for the page the popup was opened on. */
async function showCurrentSite(accounts) {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!/^https?:/.test(tab?.url ?? '')) return;

  const host = cleanHost(tab.url);
  const rule = findRule(await loadRules(), host);
  $('host').value = rule?.host ?? host;
  if (rule) {
    $('account').value = rule.account;
    $('submit').checked = rule.submit;
    return;
  }
  // Detent may already know which account this site uses, from a scan or another device.
  const known = accounts.find((account) => (account.domains ?? []).some((domain) => hostMatches(host, domain)));
  if (known) $('account').value = known.id;
}

$('add').addEventListener('submit', async (event) => {
  event.preventDefault();
  const host = cleanHost($('host').value);
  const account = $('account').selectedOptions[0];
  if (!host || !account) return;

  const rule = { host, account: account.value, label: account.text, submit: $('submit').checked };
  await saveRules([...(await loadRules()).filter((other) => other.host !== host), rule]);
  await rememberSite(host, account.value, true);
  await showRules();
  await requestAccess(host);
  showRules();
});

showRules();
showAccounts().then(showCurrentSite);
