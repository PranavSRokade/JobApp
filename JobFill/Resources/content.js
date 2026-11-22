// JobFill's page script. It loads on every page but does nothing until the popup asks: then it
// reads each form field's clues (label, placeholder, name, id, accessibility label, group
// question, autofill hint), fills what it recognises from the saved details, asks the worker
// about the labels it doesn't, and outlines everything it touched so it can be checked.

const FIELD_SELECTOR = 'input, textarea, select, [role="combobox"]:not(input), button[aria-haspopup="listbox"]';
const SKIP_INPUT_TYPES = new Set(['hidden', 'submit', 'button', 'reset', 'image', 'password', 'search', 'range', 'color']);
const MIN_FIELDS = 2; // a frame with fewer than this is a search box or a newsletter, not a form

// --- Finding fields, including inside shadow roots ---------------------------------------

function allFields(root = document) {
    const found = Array.from(root.querySelectorAll(FIELD_SELECTOR));
    for (const el of root.querySelectorAll('*')) {
        if (el.shadowRoot) found.push(...allFields(el.shadowRoot));
    }
    return found;
}

// A dropdown the site draws itself (React Select, Headless UI and the like) instead of a real
// <select>: an input or button that opens a list of role="option" items.
function isCombo(el) {
    if (el.tagName === 'SELECT' || el.tagName === 'TEXTAREA') return false;
    return el.getAttribute('role') === 'combobox'
        || el.getAttribute('aria-haspopup') === 'listbox'
        || (el.tagName === 'INPUT' && !!el.getAttribute('aria-autocomplete') && el.getAttribute('aria-autocomplete') !== 'none');
}

function isVisible(el) {
    if (el.disabled || el.getAttribute('aria-disabled') === 'true') return false;
    if (el.readOnly && !isCombo(el)) return false;
    if (el.tagName === 'INPUT' && SKIP_INPUT_TYPES.has(el.type)) return false;
    const box = el.getBoundingClientRect();
    if (el.type === 'radio' || el.type === 'checkbox' || el.type === 'file') {
        // Custom-styled ones hide the real input; their label is what shows.
        const label = el.labels && el.labels[0];
        if (label) {
            const lb = label.getBoundingClientRect();
            if (lb.width > 0 && lb.height > 0) return true;
        }
    }
    if (box.width === 0 || box.height === 0) return false;
    const style = getComputedStyle(el);
    return style.visibility !== 'hidden' && style.display !== 'none';
}

// --- Reading clues ------------------------------------------------------------------------

function clean(text) {
    return (text || '').replace(/\s+/g, ' ').trim();
}

function textOf(el) {
    if (!el) return '';
    const copy = el.cloneNode(true);
    copy.querySelectorAll(`${FIELD_SELECTOR}, script, style, option`).forEach((n) => n.remove());
    return clean(copy.textContent);
}

function byIds(el, attr) {
    const ids = (el.getAttribute(attr) || '').split(/\s+/).filter(Boolean);
    const root = el.getRootNode();
    return clean(ids.map((id) => textOf(root.getElementById ? root.getElementById(id) : document.getElementById(id))).join(' '));
}

// The closest short text before the field inside its nearby containers: how most custom forms
// put their question above the input without a <label for>.
function nearbyText(el) {
    let node = el;
    for (let depth = 0; depth < 4 && node.parentElement; depth++) {
        const parent = node.parentElement;
        let sib = node.previousElementSibling;
        while (sib) {
            if (!sib.querySelector(FIELD_SELECTOR) && !sib.matches(FIELD_SELECTOR)) {
                const t = textOf(sib);
                if (t.length >= 2 && t.length <= 250) return t;
            }
            sib = sib.previousElementSibling;
        }
        node = parent;
    }
    return '';
}

// The question a radio or checkbox group answers (the options' own labels are just "Yes"/"No").
function groupQuestion(el) {
    const fieldset = el.closest('fieldset');
    if (fieldset) {
        const legend = fieldset.querySelector('legend');
        if (legend && textOf(legend)) return textOf(legend);
    }
    const group = el.closest('[role="radiogroup"], [role="group"]');
    if (group) {
        const t = group.getAttribute('aria-label') || byIds(group, 'aria-labelledby');
        if (t) return clean(t);
    }
    const label = el.labels && el.labels[0];
    return nearbyText(label && label.contains(el) ? label : (label ? label : el));
}

function ownLabel(el) {
    const parts = [];
    if (el.getAttribute('aria-labelledby')) parts.push(byIds(el, 'aria-labelledby'));
    if (el.labels) for (const l of el.labels) parts.push(textOf(l));
    if (el.getAttribute('aria-label')) parts.push(el.getAttribute('aria-label'));
    const wrapping = el.closest('label');
    if (wrapping) parts.push(textOf(wrapping));
    return clean(parts.filter(Boolean).join(' '));
}

function cluesFor(el) {
    const isChoice = el.type === 'radio' || el.type === 'checkbox';
    const label = isChoice ? groupQuestion(el) : (ownLabel(el) || nearbyText(el));
    const extra = [el.placeholder, el.name, el.id, el.getAttribute('data-qa'), el.getAttribute('data-testid')]
        .filter(Boolean)
        .join(' ')
        .replace(/[_\-[\]]+/g, ' ')
        .replace(/([a-z])([A-Z])/g, '$1 $2');
    return {
        label,
        extra: clean(extra),
        autocomplete: (el.getAttribute('autocomplete') || '').toLowerCase().trim(),
        required: el.required || el.getAttribute('aria-required') === 'true' || /\*\s*$/.test(label),
    };
}

// --- Rules ---------------------------------------------------------------------------------

const AUTOCOMPLETE_KEYS = {
    'given-name': 'firstName',
    'family-name': 'lastName',
    name: 'fullName',
    email: 'email',
    tel: 'phone',
    'tel-national': 'phone',
    'address-level2': 'city',
    country: 'country',
    'country-name': 'country',
};

// Order matters: the first rule that matches wins, so narrow ones sit above broad ones.
const RULES = [
    ['skip', /\b(company|employer|referr\w*|reference|recruiter|manager|school|university|college|emergency|captcha|search|password|coupon|promo|code of conduct|gender|pronoun|ethnic\w*|race|disabilit\w*|veteran|sexual)\b/],
    ['rightToWorkNoSponsor', /without (the need for |needing |requiring |any )?(a |visa |employer )*sponsor/],
    ['needsSponsorship', /sponsor/],
    ['rightToWork', /right to work|(authori[sz]ed|eligible|entitled|permitted|allowed|able) to work|work (permit|authori[sz]ation|eligibility)/],
    ['firstName', /\b(first|given|fore) ?name\b|\bfname\b/],
    ['lastName', /\b(last|family|sur) ?name\b|\bsurname\b|\blname\b/],
    ['fullName', /\bfull ?name\b|\blegal name\b|\byour name\b|^name\b\W*$/],
    ['email', /\be-?mail\b/],
    ['phone', /\b(phone|mobile|telephone|tel|cell)\b/],
    ['linkedin', /linked ?in/],
    ['github', /git ?hub/],
    ['portfolio', /portfolio|personal (web ?)?site|\bwebsite\b|^url$|\bother (link|url)/],
    ['country', /\bcountry\b(?! code)/],
    ['city', /\b(city|town)\b/],
    ['location', /\blocation\b|where (are|do) you (currently )?(based|live|located)|\bbased in\b|current address/],
    ['noticePeriod', /notice|earliest start|start date|when can you start|availab\w* to start/],
    ['salaryExpectation', /salary|compensation|pay expectation|expected (pay|rate)|desired (pay|rate)/],
];

function ruleKey(text) {
    const t = text.toLowerCase();
    for (const [key, re] of RULES) if (re.test(t)) return key;
    return null;
}

function savedAnswerKey(label, apply) {
    const l = label.toLowerCase().replace(/[^a-z0-9 ]/g, '').trim();
    if (l.length < 6) return null;
    const i = (apply.answers || []).findIndex((a) => {
        const q = a.question.toLowerCase().replace(/[^a-z0-9 ]/g, '').trim();
        return q && (l.includes(q) || q.includes(l));
    });
    return i >= 0 ? `answer:${i}` : null;
}

function keyFor(clues, apply) {
    if (clues.autocomplete && AUTOCOMPLETE_KEYS[clues.autocomplete]) return AUTOCOMPLETE_KEYS[clues.autocomplete];
    if (clues.label) {
        const saved = savedAnswerKey(clues.label, apply);
        if (saved) return saved;
        const k = ruleKey(clues.label);
        if (k) return k;
    }
    return clues.extra ? ruleKey(clues.extra) : null;
}

// --- Values ---------------------------------------------------------------------------------

function yesNo(v) {
    return v === 'yes' ? 'Yes' : v === 'no' ? 'No' : '';
}

function valueFor(key, apply) {
    if (key.startsWith('answer:')) {
        const a = (apply.answers || [])[Number(key.slice(7))];
        return a ? a.answer : '';
    }
    switch (key) {
        case 'fullName': return clean(`${apply.firstName} ${apply.lastName}`);
        case 'location': return [apply.city, apply.country].filter(Boolean).join(', ');
        case 'rightToWork': return yesNo(apply.rightToWork);
        case 'needsSponsorship': return yesNo(apply.needsSponsorship);
        case 'rightToWorkNoSponsor':
            if (!apply.rightToWork || !apply.needsSponsorship) return '';
            return apply.rightToWork === 'yes' && apply.needsSponsorship === 'no' ? 'Yes' : 'No';
        case 'skip': return '';
        default: return apply[key] || '';
    }
}

const COUNTRY_ALIASES = { 'united kingdom': ['united kingdom', 'uk', 'u.k.', 'great britain', 'gb', 'england'] };

function optionMatches(optionText, value) {
    const o = optionText.toLowerCase().trim();
    const v = value.toLowerCase().trim();
    if (!o || !v) return false;
    if (v === 'yes' || v === 'no') return o === v || o.startsWith(`${v},`) || o.startsWith(`${v} `) || o.startsWith(`${v}-`) || o.startsWith(`${v}.`);
    const aliases = COUNTRY_ALIASES[v] || [v];
    return aliases.some((a) => o === a || o.startsWith(`${a} `) || o.startsWith(`${a} (`) || o.includes(a) && a.length > 3);
}

// --- Writing values so the page's own code (React, Vue…) notices --------------------------

function nativeSet(el, value) {
    const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype
        : el instanceof HTMLSelectElement ? HTMLSelectElement.prototype
        : HTMLInputElement.prototype;
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
}

function fire(el) {
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    el.dispatchEvent(new Event('blur', { bubbles: true }));
}

function fillText(el, value) {
    if (el.value && el.value.trim()) return false; // never overwrite what's there
    el.focus({ preventScroll: true });
    nativeSet(el, value);
    fire(el);
    return Boolean(el.value); // a date or number field rejects text it can't parse
}

function fillSelect(el, value) {
    if (el.selectedIndex > 0 && el.value) return false;
    const option = Array.from(el.options).find((o) => o.value && optionMatches(o.textContent, value));
    if (!option) return false;
    nativeSet(el, option.value);
    fire(el);
    return true;
}

function fillChoice(group, value) {
    if (group.some((r) => r.checked)) return false;
    const pick = group.find((r) => optionMatches(ownLabel(r) || r.value, value));
    if (!pick) return false;
    pick.click();
    if (!pick.checked) { pick.checked = true; fire(pick); }
    return true;
}

// --- Custom dropdowns ------------------------------------------------------------------------

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitFor(find, timeoutMs) {
    const end = Date.now() + timeoutMs;
    while (Date.now() < end) {
        const hit = find();
        if (hit) return hit;
        await sleep(100);
    }
    return null;
}

// Real taps fire pointer and mouse events in this order; libraries listen to different ones.
function press(el) {
    for (const type of ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click']) {
        const Ev = type.startsWith('pointer') && window.PointerEvent ? PointerEvent : MouseEvent;
        el.dispatchEvent(new Ev(type, { bubbles: true, cancelable: true, composed: true, view: window }));
    }
}

// Whether the dropdown still shows its placeholder. Its own input stays empty even after a choice,
// so this looks at the boxes around it for a chosen value or a placeholder.
function comboIsEmpty(el) {
    if (el.tagName !== 'INPUT') {
        const t = textOf(el).toLowerCase();
        return !t || /^(select|choose|please|--|pick)/.test(t);
    }
    let node = el;
    for (let depth = 0; depth < 4 && node.parentElement; depth++) {
        node = node.parentElement;
        // Stop at the dropdown's own box: one level more and it would see a neighbour's choice.
        const fields = Array.from(node.querySelectorAll(FIELD_SELECTOR)).filter((f) => f.type !== 'hidden');
        if (fields.length > 1) break;
        if (node.querySelector('[class*="single-value" i], [class*="singlevalue" i], [class*="multi-value" i], [class*="multivalue" i]')) return false;
        if (node.querySelector('[class*="placeholder" i]')) return true;
    }
    return !(el.value && el.value.trim());
}

function visibleOptions(el) {
    const root = el.getRootNode();
    const lookup = (id) => (root.getElementById ? root.getElementById(id) : document.getElementById(id));
    const ids = `${el.getAttribute('aria-controls') || ''} ${el.getAttribute('aria-owns') || ''}`.split(/\s+/).filter(Boolean);
    let scopes = ids.map(lookup).filter(Boolean);
    if (!scopes.length) scopes = root === document ? [document] : [root, document];
    const seen = new Set();
    const out = [];
    for (const scope of scopes) {
        for (const o of scope.querySelectorAll('[role="option"], [class*="__option" i]:not([class*="__options" i]), [class*="-option" i]:not([class*="-options" i])')) {
            if (seen.has(o) || o.getAttribute('aria-disabled') === 'true') continue;
            seen.add(o);
            const box = o.getBoundingClientRect();
            if (box.width > 0 && box.height > 0) out.push(o);
        }
    }
    return out;
}

async function fillCombo(el, key, value, apply) {
    if (!comboIsEmpty(el)) return false;
    // Location boxes search places as you type, so search the city and take the first match.
    const want = key === 'location' && apply.city ? apply.city : value;
    const typeable = el.tagName === 'INPUT' && !el.readOnly;
    el.focus({ preventScroll: true });
    press(el);
    if (typeable) {
        nativeSet(el, want);
        el.dispatchEvent(new Event('input', { bubbles: true }));
    }
    // Some lists ignore a synthetic tap but open on the Down arrow, the standard key for any
    // accessible dropdown.
    if (!(await waitFor(() => visibleOptions(el).length > 0, 400))) {
        el.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', code: 'ArrowDown', keyCode: 40, bubbles: true }));
    }
    const option = await waitFor(
        () => visibleOptions(el).find((o) => optionMatches(clean(o.textContent), want)),
        key === 'location' ? 3000 : 1500,
    );
    if (!option) {
        if (typeable) { nativeSet(el, ''); el.dispatchEvent(new Event('input', { bubbles: true })); }
        el.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true }));
        el.blur();
        return false;
    }
    if (option.scrollIntoView) option.scrollIntoView({ block: 'nearest' });
    press(option);
    await sleep(150);
    el.blur();
    return !comboIsEmpty(el);
}

// --- Marking ------------------------------------------------------------------------------

const STYLE_ID = 'jobfill-style';
function ensureStyle(root) {
    const host = root instanceof ShadowRoot ? root : document.head;
    if (!host || (host.querySelector && host.querySelector(`#${STYLE_ID}`))) return;
    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = `
        [data-jobfill="filled"] { outline: 2px solid #534ab7 !important; outline-offset: 1px !important; }
        [data-jobfill="need"] { outline: 2px dashed #e8833a !important; outline-offset: 1px !important; }`;
    host.appendChild(style);
}

function comboBox(el) {
    let node = el;
    while (node.parentElement && node.getBoundingClientRect().height < 24) node = node.parentElement;
    return node;
}

function mark(el, state) {
    const target = (el.type === 'radio' || el.type === 'checkbox' || el.type === 'file')
        ? (el.closest('fieldset, [role="radiogroup"], [role="group"]') || (el.labels && el.labels[0]) || el)
        : isCombo(el) && el.tagName === 'INPUT' ? comboBox(el) : el;
    ensureStyle(target.getRootNode());
    target.setAttribute('data-jobfill', state);
}

// --- One pass over the page -----------------------------------------------------------------

// Radios and checkboxes sharing a name are one question; everything else is its own item.
function collectItems() {
    const items = [];
    const groups = new Map();
    for (const el of allFields()) {
        if (!isVisible(el)) continue;
        if (el.type === 'radio' || el.type === 'checkbox') {
            const k = `${el.type}:${el.name || el.id}`;
            if (!el.name && el.type === 'checkbox') { items.push({ kind: 'consent', els: [el] }); continue; }
            if (!groups.has(k)) { groups.set(k, { kind: 'choice', els: [] }); items.push(groups.get(k)); }
            groups.get(k).els.push(el);
        } else if (el.type === 'file') {
            items.push({ kind: 'file', els: [el] });
        } else if (isCombo(el)) {
            items.push({ kind: 'combo', els: [el] });
        } else if (el.tagName === 'SELECT') {
            items.push({ kind: 'select', els: [el] });
        } else if (el.tagName === 'TEXTAREA') {
            items.push({ kind: 'longText', els: [el] });
        } else {
            items.push({ kind: 'text', els: [el] });
        }
    }
    for (const item of items) item.clues = cluesFor(item.els[0]);
    return items;
}

function isEmpty(item) {
    const el = item.els[0];
    if (item.kind === 'choice' || item.kind === 'consent') return !item.els.some((r) => r.checked);
    if (item.kind === 'select') return !(el.selectedIndex > 0 && el.value);
    if (item.kind === 'combo') return comboIsEmpty(el);
    if (item.kind === 'file') return !(el.files && el.files.length);
    return !(el.value && el.value.trim());
}

async function fillItem(item, key, apply) {
    const value = valueFor(key, apply);
    if (!value) return false;
    const el = item.els[0];
    if (item.kind === 'combo') return fillCombo(el, key, value, apply);
    if (item.kind === 'choice') return fillChoice(item.els, value);
    if (item.kind === 'select') return fillSelect(el, value);
    if (item.kind === 'text') return fillText(el, value);
    if (item.kind === 'longText' && key.startsWith('answer:')) return fillText(el, value);
    return false;
}

function optionsOf(item) {
    if (item.kind === 'select') return Array.from(item.els[0].options).map((o) => clean(o.textContent)).filter(Boolean);
    if (item.kind === 'choice') return item.els.map((r) => ownLabel(r) || r.value).filter(Boolean);
    return [];
}

async function fillPage(apply) {
    const items = collectItems();
    let filled = 0;
    const unknown = [];

    for (const item of items) {
        if (!isEmpty(item) || item.kind === 'file' || item.kind === 'consent') continue;
        const key = keyFor(item.clues, apply);
        if (key && key !== 'skip') {
            if (await fillItem(item, key, apply)) { filled++; mark(item.els[0], 'filled'); }
        } else if (!key && item.clues.label && item.kind !== 'longText') {
            unknown.push(item);
        }
    }

    if (unknown.length) {
        const reply = await browser.runtime.sendMessage({
            type: 'matchLabels',
            fields: unknown.map((item) => ({ label: item.clues.label.slice(0, 200), options: optionsOf(item) })),
        });
        if (reply && reply.ok) {
            for (let i = 0; i < unknown.length; i++) {
                const key = reply.keys[i];
                if (key && await fillItem(unknown[i], key, apply)) { filled++; mark(unknown[i].els[0], 'filled'); }
            }
        }
    }

    let needYou = 0;
    for (const item of items) {
        if (item.clues.required && isEmpty(item)) { needYou++; mark(item.els[0], 'need'); }
    }
    return { host: location.hostname, fields: items.length, filled, needYou };
}

// --- The on-page button --------------------------------------------------------------------
// Shown once a page looks like a job application, so filling is one tap instead of opening the
// extension menu. It lives in its own shadow root so the site's styles can't reach it.

const CONTACT_KEYS = new Set(['firstName', 'lastName', 'fullName', 'email', 'phone', 'linkedin']);
const JOB_WORDS = /apply|application|career|job|candidate|resume|vacanc|hiring|recruit/i;
let pillHost = null;
let pillDismissed = false;

function looksLikeApplication() {
    if (document.querySelectorAll('input, textarea, select').length < 3) return false; // cheap first look
    const items = collectItems();
    if (items.length < 3) return false;
    const contact = items.filter((i) => CONTACT_KEYS.has(keyFor(i.clues, { answers: [] }))).length;
    const cv = items.some((i) => i.kind === 'file' && /resume|\bcv\b|curriculum/i.test(`${i.clues.label} ${i.clues.extra}`));
    const heading = document.querySelector('h1, h2');
    const context = `${location.href} ${document.title} ${heading ? heading.textContent : ''}`;
    return contact >= 2 && (cv || JOB_WORDS.test(context));
}

function showPill() {
    pillHost = document.createElement('div');
    pillHost.setAttribute('data-jobfill-pill', '');
    pillHost.style.cssText = 'position:fixed;right:16px;bottom:calc(16px + env(safe-area-inset-bottom));z-index:2147483647;';
    const shadow = pillHost.attachShadow({ mode: 'closed' });
    shadow.innerHTML = `
        <style>
            .pill { display:flex; align-items:center; gap:4px; padding:4px; border-radius:999px; background:#534ab7;
                    box-shadow:0 4px 16px rgba(0,0,0,.25); font:600 15px -apple-system,system-ui,sans-serif; color:#fff; }
            button { border:0; background:transparent; color:inherit; font:inherit; padding:8px 12px; border-radius:999px; }
            .close { padding:8px 10px; opacity:.8; }
            .msg { padding:0 4px 0 10px; font-weight:500; }
        </style>
        <div class="pill"><button class="fill">Fill with JobFill</button><span class="msg" hidden></span><button class="close" aria-label="Hide">✕</button></div>`;
    const fillBtn = shadow.querySelector('.fill');
    const msg = shadow.querySelector('.msg');
    shadow.querySelector('.close').addEventListener('click', () => { pillDismissed = true; pillHost.remove(); });
    fillBtn.addEventListener('click', async () => {
        fillBtn.disabled = true;
        fillBtn.textContent = 'Filling…';
        let text;
        try {
            const reply = await browser.runtime.sendMessage({ type: 'applyProfile' });
            if (!reply || !reply.ok) throw new Error(reply ? reply.error : 'no reply');
            const res = await fillPage(reply.apply);
            text = `Filled ${res.filled}${res.needYou ? ` · ${res.needYou} need you` : ''}`;
        } catch (err) {
            text = `Couldn't fill: ${err.message || err}`;
        }
        fillBtn.hidden = true;
        msg.hidden = false;
        msg.textContent = text;
    });
    document.documentElement.appendChild(pillHost);
}

function checkForForm() {
    if (pillHost || pillDismissed) return;
    try { if (looksLikeApplication()) showPill(); } catch (e) { /* never break the page */ }
}

// Forms often appear after the page loads (an Apply tab, a single-page app), so keep looking for
// two minutes after load, but only once the page has been quiet for a moment.
(function watchForForm() {
    let timer = null;
    const observer = new MutationObserver(() => {
        clearTimeout(timer);
        timer = setTimeout(() => { checkForForm(); if (pillHost) observer.disconnect(); }, 800);
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
    setTimeout(() => observer.disconnect(), 120000);
    setTimeout(checkForForm, 300);
})();

browser.runtime.onMessage.addListener((message) => {
    if (!message) return undefined;
    if (message.type === 'scan') {
        const count = collectItems().length;
        if (count < MIN_FIELDS) return undefined; // let the frame that holds the form answer
        return Promise.resolve({ host: location.hostname, fields: count });
    }
    if (message.type === 'fill') {
        if (collectItems().length < MIN_FIELDS) return undefined;
        return fillPage(message.apply).catch((err) => ({ error: String(err.message || err) }));
    }
    return undefined;
});
