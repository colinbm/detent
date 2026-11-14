// Runs on the sites that have a rule. Watches for a field that wants a two-factor code and
// fills it in. The code is only asked for once such a field is on the page.
(() => {
  if (globalThis.sesameLoaded) return;
  globalThis.sesameLoaded = true;

  const HINT = /otp|2fa|mfa|one[-_ ]?time|verif|two[-_ ]?(factor|step)|authenticat(or|ion)[-_ ]?(code|app)|(security|auth|login|access)[-_ ]?code|passcode/i;
  const TEXT_TYPES = ['text', 'tel', 'number', 'password'];
  const NOT_A_CODE = ['username', 'email', 'current-password', 'new-password'];
  // When the code last filled in on this tab runs out. Kept across reloads.
  const USED_UNTIL = 'sesame-used-until';

  const tried = new WeakSet();
  let busy = false;

  function usable(input) {
    if (tried.has(input) || !TEXT_TYPES.includes(input.type)) return false;
    if (input.disabled || input.readOnly || input.value !== '') return false;
    return input.getClientRects().length > 0 && getComputedStyle(input).visibility !== 'hidden';
  }

  function looksLikeCode(input) {
    if (NOT_A_CODE.includes(input.autocomplete)) return false;
    const labels = [...(input.labels ?? [])].map((label) => label.textContent);
    const described = [input.name, input.id, input.placeholder, input.getAttribute('aria-label'), ...labels];
    return HINT.test(described.join(' '));
  }

  /** The inputs to fill: one field, or a row of single-character boxes. Null if there are none. */
  function findFields() {
    const inputs = [...document.querySelectorAll('input')].filter(usable);
    const boxes = inputs.filter((input) => input.maxLength === 1);
    if (boxes.length >= 6 && boxes.length <= 9) return boxes;

    const field = inputs.find((input) => input.autocomplete.split(' ').includes('one-time-code'))
      ?? inputs.find(looksLikeCode);
    return field ? [field] : null;
  }

  // Assigning to `value` directly is invisible to React and friends, which track it themselves.
  const setValue = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
  function type(input, text) {
    input.focus();
    setValue.call(input, text);
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
  }

  function submit(input) {
    if (input.form) {
      input.form.requestSubmit();
      return;
    }
    for (const name of ['keydown', 'keypress', 'keyup']) {
      input.dispatchEvent(new KeyboardEvent(name, { key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true }));
    }
  }

  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const requestCode = () => chrome.runtime.sendMessage({ type: 'code' }).catch(() => ({}));

  function usedUntil() {
    try {
      return Number(sessionStorage.getItem(USED_UNTIL)) || 0;
    } catch {
      return 0;
    }
  }

  async function fill(fields) {
    // A code that was just entered here either worked or was refused, so entering it again
    // can only fail, and with automatic submission would do so in a loop. Wait for the next.
    const wait = usedUntil() - Date.now();
    if (wait > 0) await sleep(wait + 250);

    let reply = await requestCode();
    // Too close to expiry to arrive in time.
    if (reply.code && reply.remaining < 3) {
      await sleep(reply.remaining * 1000 + 250);
      reply = await requestCode();
    }
    if (!reply.code) return;

    // The page may have moved on, or the user started typing, while the code was fetched.
    if (!fields.every((field) => field.isConnected && field.value === '')) return;

    if (fields.length === 1) {
      type(fields[0], reply.code);
    } else if (fields.length === reply.code.length) {
      fields.forEach((field, index) => type(field, reply.code[index]));
    } else {
      return;
    }

    try {
      sessionStorage.setItem(USED_UNTIL, String(Date.now() + reply.remaining * 1000));
    } catch {}
    if (reply.submit) submit(fields.at(-1));
  }

  async function check() {
    if (busy) return;
    const fields = findFields();
    if (!fields) return;
    busy = true;
    // One attempt per field, whatever happens, so a failure is not retried on every page change.
    fields.forEach((field) => tried.add(field));
    try {
      await fill(fields);
    } finally {
      busy = false;
    }
  }

  // Sign-in pages often add the code field later, or reveal one that was hidden.
  let timer;
  new MutationObserver(() => {
    clearTimeout(timer);
    timer = setTimeout(check, 300);
  }).observe(document.documentElement, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ['class', 'style', 'hidden'],
  });
  check();
})();
