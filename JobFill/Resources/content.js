// JobFill's page script. It loads on every page but does nothing until the popup asks: then it
// reads each form field's clues (label, placeholder, name, id, accessibility label, group
// question, autofill hint), fills what it recognises from the saved details, asks the worker
// about the labels it doesn't, and outlines everything it touched so it can be checked.

const FIELD_SELECTOR = 'input, textarea, select, [role="combobox"]:not(input), button[aria-haspopup="listbox"], [role="radio"]:not(input), button[aria-pressed]';
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

// A choice drawn as buttons instead of radio inputs: Ashby's Yes/No pair (aria-pressed) or a
// custom radio widget (role="radio").
function isChoiceButton(el) {
    return (el.getAttribute('role') === 'radio' && el.tagName !== 'INPUT')
        || (el.tagName === 'BUTTON' && el.hasAttribute('aria-pressed'));
}

function isChosen(el) {
    return Boolean(el.checked) || el.getAttribute('aria-pressed') === 'true' || el.getAttribute('aria-checked') === 'true';
}

function choiceText(el) {
    return isChoiceButton(el) ? clean(el.getAttribute('aria-label') || textOf(el)) : (ownLabel(el) || el.value);
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
        } else if (el.type !== 'file' && el.parentElement && getComputedStyle(el).display === 'none') {
            // An unlabelled hidden radio inside a styled box the user taps
            const pb = el.parentElement.getBoundingClientRect();
            if (pb.width > 0 && pb.height > 0) return true;
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
    return clean([...new Set(parts.map(clean).filter(Boolean))].join(' ')); // a wrapping label is also in el.labels
}

function cluesFor(el) {
    const isChoice = el.type === 'radio' || el.type === 'checkbox' || isChoiceButton(el);
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
    if (group.some(isChosen)) return false;
    const pick = group.find((r) => optionMatches(choiceText(r), value));
    if (!pick) return false;
    if (isChoiceButton(pick)) {
        press(pick);
        return true;
    }
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
        [data-jobfill="need"] { outline: 2px dashed #e8833a !important; outline-offset: 1px !important; }
        [data-jobfill="drafted"] { outline: 2px dashed #534ab7 !important; outline-offset: 1px !important; }`;
    host.appendChild(style);
}

function comboBox(el) {
    let node = el;
    while (node.parentElement && node.getBoundingClientRect().height < 24) node = node.parentElement;
    return node;
}

function mark(el, state) {
    const target = isChoiceButton(el) ? (el.closest('[role="radiogroup"]') || el.parentElement)
        : (el.type === 'radio' || el.type === 'checkbox' || el.type === 'file')
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
    const buttonGroups = new Map(); // container element → item
    for (const el of allFields()) {
        if (!isVisible(el)) continue;
        if (isChoiceButton(el)) {
            const box = el.closest('[role="radiogroup"]') || el.parentElement;
            if (!buttonGroups.has(box)) { buttonGroups.set(box, { kind: 'choice', els: [] }); items.push(buttonGroups.get(box)); }
            buttonGroups.get(box).els.push(el);
            continue;
        }
        // Ashby keeps a hidden checkbox next to its Yes/No buttons; the buttons are the question
        if (el.tagName === 'INPUT' && el.parentElement && el.parentElement.querySelector('button[aria-pressed], [role="radio"]:not(input)')) continue;
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
    // A lone aria-pressed button is a toggle (bold, show more…), not a question
    const real = items.filter((item) => !(isChoiceButton(item.els[0]) && item.els.length < 2));
    for (const item of real) item.clues = cluesFor(item.els[0]);
    return real;
}

function isEmpty(item) {
    const el = item.els[0];
    if (item.kind === 'choice' || item.kind === 'consent') return !item.els.some(isChosen);
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
    if (item.kind === 'choice') return item.els.map(choiceText).filter(Boolean);
    return [];
}

async function fillPage(apply, progress = () => {}) {
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

    // The slow part runs together: one drafted answer per open question, and the CV you made for
    // this job in JobApp (found on the worker by company and title)
    lastApply = apply;
    // The CV and cover letter you made for this job in JobApp (found on the worker by company and
    // title) come first: the CV's text grounds the drafted answers, the files go in the upload fields
    const cv = cvInput();
    const letterBox = letterInput();
    let drafted = 0;
    let cvState = null;
    let letterState = null;
    progress(`Filled ${filled} · looking for your CV…`);
    const job = await currentJob();
    await findAppCv(job).catch(() => {});
    if (cv) {
        cvState = !job.cv ? 'none' : attachFile(cv, pdfFile(job.cv, job.cvName)) ? 'attached' : 'save';
        if (cvState === 'attached') mark(cv, 'filled');
    }
    if (letterBox) {
        letterState = !job.letter ? 'none' : attachFile(letterBox, pdfFile(job.letter.pdf, job.letter.fileName)) ? 'attached' : 'save';
        if (letterState === 'attached') mark(letterBox, 'filled');
    }
    // A cover-letter text box takes the letter you made; with none, it is drafted like any question
    for (const item of items) {
        if (item.kind === 'longText' && isEmpty(item) && job.letter && job.letter.text && /cover\s*letter/i.test(item.clues.label)
            && fillText(item.els[0], job.letter.text)) { filled++; mark(item.els[0], 'filled'); }
    }

    const drafts = items.filter((item) => wantsDraft(item, apply));
    if (drafts.length) progress(`Filled ${filled} · writing answers…`);
    const about = job.jd || `${job.title} at ${job.company}`;
    await Promise.all(drafts.map((item) => browser.runtime.sendMessage({
        type: 'answer', jd: about, company: job.company, title: job.title, question: questionOf(item), latex: job.latex || null,
    }).then((reply) => {
        if (reply && reply.ok && isEmpty(item) && fillText(item.els[0], reply.text)) { drafted++; mark(item.els[0], 'drafted'); }
    }).catch(() => {})));

    // Required questions nothing could answer go to you, one at a time, and are remembered
    questions = items.filter((item) => item.clues.required && isEmpty(item) && askable(item, apply));

    let needYou = 0;
    for (const item of items) {
        if (item.clues.required && isEmpty(item)) { needYou++; mark(item.els[0], 'need'); }
    }
    await currentJob();
    rememberJob();
    return { host: location.hostname, fields: items.length, filled, needYou, drafted, cv: cvState, letter: letterState, questions: questions.length };
}

// --- The job this form is for --------------------------------------------------------------
// Title, company and description are guesses from the page; the Mark applied card lets you fix them.

const ATS_HOSTS = /(lever\.co|greenhouse\.io|ashbyhq\.com|workable\.com|smartrecruiters\.com|teamtailor\.com|recruitee\.com|bamboohr\.com|personio\.(de|com))$/i;
let job = null; // filled in on the first Fill, kept for Mark applied

function metaContent(name) {
    const el = document.querySelector(`meta[property="${name}"], meta[name="${name}"]`);
    return el ? clean(el.getAttribute('content')) : '';
}

function titleCase(text) {
    return text.replace(/\b\w/g, (c) => c.toUpperCase());
}

function postingUrl() {
    const url = new URL(location.href);
    url.search = '';
    url.hash = '';
    return url.href.replace(/\/apply\/?$/, '');
}

function companyGuess() {
    const host = location.hostname.replace(/^www\./, '');
    if (ATS_HOSTS.test(host)) {
        const sub = host.split('.')[0];
        const slug = ['jobs', 'boards', 'job-boards', 'apply', 'careers'].includes(sub) ? location.pathname.split('/').filter(Boolean)[0] : sub;
        if (slug) return titleCase(decodeURIComponent(slug).replace(/[-_]+/g, ' '));
    }
    const site = metaContent('og:site_name');
    if (site && !/lever|greenhouse|ashby|workable|linkedin|indeed/i.test(site)) return site;
    const parts = host.split('.');
    return titleCase(parts.length > 2 && ['careers', 'jobs', 'apply', 'join'].includes(parts[0]) ? parts[1] : parts[0]);
}

function titleGuess(company) {
    const raw = metaContent('og:title') || clean(document.title);
    const lowerCompany = company.toLowerCase();
    const piece = raw.replace(/^job application for\s+/i, '')
        .split(/\s+(?:[-–|@]|at)\s+/i)
        .map(clean)
        .find((p) => p && !p.toLowerCase().includes(lowerCompany) && !lowerCompany.includes(p.toLowerCase()));
    const heading = document.querySelector('h1, h2');
    return (piece || (heading && clean(heading.textContent)) || raw).slice(0, 200);
}

// On most boards the job description is the biggest block of text holding no form fields
function descriptionIn(doc) {
    let best = null;
    let bestLength = 0;
    for (const el of doc.querySelectorAll('main, article, section, div')) {
        const length = (el.textContent || '').length;
        if (length <= bestLength || el.querySelector('input, textarea, select')) continue;
        best = el;
        bestLength = length;
    }
    if (!best) return '';
    return clean(best.innerText || best.textContent).slice(0, 12000);
}

async function jobDescription() {
    let jd = descriptionIn(document);
    // Lever-style /apply pages hold only the form; the description is one level up
    if (jd.length < 400 && /\/apply\/?$/.test(location.pathname)) {
        try {
            const html = await (await fetch(postingUrl(), { credentials: 'include' })).text();
            const other = descriptionIn(new DOMParser().parseFromString(html, 'text/html'));
            if (other.length > jd.length) jd = other;
        } catch (e) { /* keep what this page has */ }
    }
    return jd;
}

async function currentJob() {
    if (job) return job;
    const company = companyGuess();
    job = {
        title: titleGuess(company), company, link: postingUrl(), location: '', jd: await jobDescription(),
        jobId: null, cv: null, cvName: null, latex: null, letter: null,
    };
    return job;
}

// --- Drafted answers and the CV ------------------------------------------------------------

const QUESTION_WORDS = /\?|\bwhy\b|\bdescribe\b|\btell us\b|\bcover letter\b|\bexplain\b|\bwhat\b|\bhow\b/i;

// Every empty required text box gets a draft; an optional one only when it asks a question
function wantsDraft(item, apply) {
    if (item.kind !== 'longText' || !item.clues.label || !isEmpty(item)) return false;
    if (keyFor(item.clues, apply) === 'skip') return false;
    return item.clues.required || QUESTION_WORDS.test(item.clues.label);
}

// File inputs are often visually hidden behind an "Attach" button, so look past visibility here
function fileInputs() {
    return allFields()
        .filter((el) => el.type === 'file' && !(el.files && el.files.length))
        .map((el) => ({ el, clues: cluesFor(el) }));
}

function cvInput() {
    const found = fileInputs().find(({ clues }) => /resume|\bcv\b|curriculum/i.test(`${clues.label} ${clues.extra}`) && !/cover/i.test(clues.label));
    return found ? found.el : null;
}

function letterInput() {
    const found = fileInputs().find(({ clues }) => /cover/i.test(`${clues.label} ${clues.extra}`));
    return found ? found.el : null;
}

// Named the way JobApp names its files: "Resume_<role>_<company>.pdf"
function documentName(prefix, job) {
    const part = (text) => clean(String(text || '').replace(/\([^)]*\)|\[[^\]]*\]/g, '').replace(/[/\\:*?"<>|_]+/g, ' '));
    return `${[prefix, part(job.title), part(job.company)].filter(Boolean).join('_')}.pdf`;
}

function pdfFile(base64, name) {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return new File([bytes], name, { type: 'application/pdf' });
}

function attachFile(input, file) {
    try {
        const transfer = new DataTransfer();
        transfer.items.add(file);
        input.files = transfer.files;
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new Event('change', { bubbles: true }));
        return input.files.length === 1;
    } catch (e) {
        return false;
    }
}

function pageContext() {
    const heading = document.querySelector('h1, h2');
    return [metaContent('og:title'), document.title, heading ? heading.textContent : '', location.hostname, location.pathname]
        .map(clean).join(' ').slice(0, 500);
}

// The CV and cover letter you made for this job in JobApp. A match also links Mark applied to that job.
async function findAppCv(job) {
    if (job.jobId) return;
    const reply = await browser.runtime.sendMessage({ type: 'preparedCv', company: job.company, context: pageContext() });
    if (!reply || !reply.ok || !reply.match) return;
    Object.assign(job, {
        jobId: reply.match.jobId, title: reply.match.title, company: reply.match.company,
        cv: reply.pdf || null, cvName: reply.match.fileName, latex: reply.latex || null, letter: reply.letter || null,
    });
    rememberJob();
}

// Only when you tap Generate CV: no CV was made for this job in the app
async function generateCv() {
    const job = await currentJob();
    const reply = await browser.runtime.sendMessage({ type: 'cv', jd: job.jd || `${job.title} at ${job.company}` });
    if (!reply || !reply.ok) return 'failed';
    job.cv = reply.pdf;
    job.cvName = documentName('Resume', job);
    job.latex = reply.latex || job.latex;
    rememberJob();
    const input = cvInput();
    if (input && attachFile(input, pdfFile(job.cv, job.cvName))) { mark(input, 'filled'); return 'attached'; }
    return 'save';
}

// Only when you tap Generate letter: grounded in the CV for this job when there is one
async function generateLetter() {
    const job = await currentJob();
    const reply = await browser.runtime.sendMessage({ type: 'coverLetter', jd: job.jd || `${job.title} at ${job.company}`, latex: job.latex || null });
    if (!reply || !reply.ok) return 'failed';
    job.letter = { pdf: reply.pdf, text: reply.text, fileName: documentName('Cover Letter', job) };
    rememberJob();
    const input = letterInput();
    if (input && attachFile(input, pdfFile(job.letter.pdf, job.letter.fileName))) { mark(input, 'filled'); return 'attached'; }
    return 'save';
}

// --- Questions for you ----------------------------------------------------------------------

let lastApply = null;
let questions = [];

function questionOf(item) {
    return item.clues.label.replace(/[*✱]/g, '').trim().slice(0, 300);
}

function askable(item, apply) {
    if (item.kind === 'file' || item.kind === 'consent' || !questionOf(item)) return false;
    const key = keyFor(item.clues, apply);
    return key !== 'skip' && !(key && valueFor(key, apply));
}

// Fills the field with your answer and saves it, so the same question fills itself next time
async function answerQuestion(item, answer) {
    const question = questionOf(item);
    const apply = { ...lastApply, answers: [...(lastApply.answers || []), { question, answer }] };
    const ok = await fillItem(item, `answer:${apply.answers.length - 1}`, apply);
    if (ok) mark(item.els[0], 'filled');
    const reply = await browser.runtime.sendMessage({ type: 'saveAnswer', question, answer }).catch(() => null);
    lastApply = reply && reply.ok ? reply.apply : apply;
    return ok;
}

// Submitting usually lands on a thank-you page, which wipes this script's memory, so the job is
// kept per site for a few hours and Mark applied is offered again there.
const PENDING_HOURS = 3;
function pendingKey() { return `pending:${location.hostname}`; }

function rememberJob() {
    if (!job) return;
    try { browser.storage.local.set({ [pendingKey()]: { ...job, at: Date.now() } }).catch(() => {}); } catch (e) { /* storage unavailable */ }
}

async function pendingJob() {
    try {
        const stored = (await browser.storage.local.get(pendingKey()))[pendingKey()];
        if (stored && Date.now() - stored.at < PENDING_HOURS * 3600 * 1000) return stored;
    } catch (e) { /* storage unavailable */ }
    return null;
}

function forgetJob() {
    try { browser.storage.local.remove(pendingKey()).catch(() => {}); } catch (e) { /* storage unavailable */ }
}

// --- The on-page button --------------------------------------------------------------------
// Shown once a page looks like a job application, so filling is one tap instead of opening the
// extension menu. It lives in a closed shadow root so the site's styles can't reach it. After a
// fill it turns into Mark applied, which adds the job (and the CV sent) to the app's Applied list.

const CONTACT_KEYS = new Set(['firstName', 'lastName', 'fullName', 'email', 'phone', 'linkedin']);
const JOB_WORDS = /apply|application|career|job|candidate|resume|vacanc|hiring|recruit/i;
const THANKS_WORDS = /thank you for (applying|your application)|thanks for applying|application (has been |was )?(received|submitted|sent)|we('|’)ve received your application|successfully (applied|submitted)/i;
let pillHost = null;
let pillShadow = null;
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

const PILL_CSS = `
    .pill { display:flex; align-items:center; flex-wrap:wrap; gap:4px; padding:4px; border-radius:22px; background:#534ab7;
            box-shadow:0 4px 16px rgba(0,0,0,.25); font:600 15px -apple-system,system-ui,sans-serif; color:#fff;
            max-width:calc(100vw - 32px); box-sizing:border-box; }
    .pill.card { flex-direction:column; align-items:stretch; gap:8px; padding:12px; border-radius:16px; width:320px; }
    button { border:0; background:transparent; color:inherit; font:inherit; padding:8px 12px; border-radius:999px; min-height:36px; }
    button.solid { background:#fff; color:#534ab7; }
    .close { padding:8px 10px; opacity:.8; }
    .msg { padding:0 4px 0 10px; font-weight:500; }
    label { display:flex; flex-direction:column; gap:3px; font-size:12px; font-weight:500; opacity:.9; }
    input { font:500 15px -apple-system,system-ui,sans-serif; padding:7px 9px; border:0; border-radius:8px; color:#1c1c1e; }
    .chances { display:grid; grid-template-columns:repeat(6, 1fr); gap:4px; }
    .chances button { padding:6px 0; background:rgba(255,255,255,.18); border-radius:8px; min-height:34px; }
    .row { display:flex; justify-content:space-between; align-items:center; }
    .hint { font-size:12px; font-weight:500; opacity:.85; }
    .question { font-weight:600; line-height:1.3; }
    textarea { font:500 15px -apple-system,system-ui,sans-serif; padding:7px 9px; border:0; border-radius:8px; color:#1c1c1e; resize:vertical; }
    .options { display:flex; flex-wrap:wrap; gap:6px; max-height:40vh; overflow:auto; }
    .options button { background:rgba(255,255,255,.18); border-radius:8px; text-align:left; }
    input:disabled { opacity:.75; }`;

function escapeHtml(text) {
    return String(text || '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}

let lastResult = null; // the last fill's summary, kept current as questions and the CV change it
let questionIndex = 0;

// state: 'ready' | 'busy' | 'done' | 'thanks' | 'ask' | 'mark' | 'added'
function renderPill(state, text = '') {
    if (pillDismissed) return;
    if (!pillHost) {
        pillHost = document.createElement('div');
        pillHost.setAttribute('data-jobfill-pill', '');
        pillHost.style.cssText = 'position:fixed;right:16px;bottom:calc(16px + env(safe-area-inset-bottom));z-index:2147483647;';
        pillShadow = pillHost.attachShadow({ mode: 'closed' });
        pillShadow.addEventListener('click', onPillClick);
        document.documentElement.appendChild(pillHost);
    }
    const close = '<button class="close" data-act="close" aria-label="Hide">✕</button>';
    const msg = text ? `<span class="msg">${escapeHtml(text)}</span>` : '';
    let body;
    if (state === 'ready') body = `<div class="pill"><button data-act="fill">Fill with JobFill</button>${close}</div>`;
    else if (state === 'busy' || state === 'added') body = `<div class="pill">${msg}${close}</div>`;
    else if (state === 'done' || state === 'thanks') {
        const cvState = state === 'done' && lastResult ? lastResult.cv : null;
        const letterState = state === 'done' && lastResult ? lastResult.letter : null;
        const cvButton = cvState === 'save' ? '<button data-act="savecv">Save CV</button>'
            : cvState === 'none' || cvState === 'failed' ? '<button data-act="gencv">Generate CV</button>' : '';
        const letterButton = letterState === 'save' ? '<button data-act="saveletter">Save letter</button>'
            : letterState === 'none' || letterState === 'failed' ? '<button data-act="genletter">Generate letter</button>' : '';
        body = `<div class="pill">${msg}${cvButton}${letterButton}<button class="solid" data-act="mark">Mark applied</button>${close}</div>`;
    } else if (state === 'ask') {
        const item = questions[questionIndex];
        const options = optionsOf(item).filter((o) => !/^(select|choose|please|--|—)/i.test(o));
        const answerBox = options.length
            ? `<div class="options">${options.map((o) => `<button data-act="option" data-v="${escapeHtml(o)}">${escapeHtml(o)}</button>`).join('')}</div>`
            : `<textarea data-f="answer" rows="${item.kind === 'longText' ? 4 : 2}"></textarea>`;
        body = `<div class="pill card">
            <div class="row"><span>Question ${questionIndex + 1} of ${questions.length}</span>${close}</div>
            <span class="question">${escapeHtml(questionOf(item))}</span>
            ${answerBox}
            <div class="row"><button data-act="skipq">Skip</button>${options.length ? '' : '<button class="solid" data-act="saveq">Save &amp; fill</button>'}</div>
            <span class="hint">Saved to your answers, so this question fills itself next time</span>
            ${msg}
        </div>`;
    } else {
        const linked = Boolean(job.jobId);
        const chances = Array.from({ length: 11 }, (_, n) => `<button data-act="chance" data-n="${n}">${n}</button>`).join('');
        body = `<div class="pill card">
            <div class="row"><span>Add to Applied</span>${close}</div>
            <label>Role<input data-f="title" value="${escapeHtml(job.title)}"${linked ? ' disabled' : ''}></label>
            <label>Company<input data-f="company" value="${escapeHtml(job.company)}"${linked ? ' disabled' : ''}></label>
            <span class="hint">${linked ? 'Your JobApp job, with its CV. ' : job.cv ? 'The CV goes with it. ' : ''}Chance of a shortlist, out of 10</span>
            <div class="chances">${chances}<button data-act="chance" data-n="">Skip</button></div>
            ${msg}
        </div>`;
    }
    pillShadow.innerHTML = `<style>${PILL_CSS}</style>${body}`;
    const box = pillShadow.querySelector('[data-f="answer"]');
    if (box) box.focus();
}

// Fields still outlined orange (mark() swaps the outline once something fills them)
function stillNeeded() {
    return document.querySelectorAll('[data-jobfill="need"]').length;
}

function doneText(res) {
    const parts = [`Filled ${res.filled}`];
    if (res.drafted) parts.push(`${res.drafted} drafted`);
    if (res.cv === 'attached') parts.push('your CV attached');
    if (res.cv === 'save') parts.push('CV ready');
    if (res.cv === 'none') parts.push('no CV for this job');
    if (res.cv === 'failed') parts.push('couldn’t make a CV');
    if (res.letter === 'attached') parts.push('cover letter attached');
    if (res.letter === 'save') parts.push('letter ready');
    if (res.letter === 'none') parts.push('no cover letter');
    if (res.letter === 'failed') parts.push('couldn’t make a letter');
    if (res.needYou) parts.push(`${res.needYou} need you`);
    return parts.join(' · ');
}

// After any fill (the on-page button or the toolbar popup): questions first, then the summary
function afterFill(res) {
    lastResult = res;
    questionIndex = 0;
    if (questions.length) renderPill('ask');
    else renderPill('done', doneText(res));
}

function nextQuestion() {
    questionIndex++;
    if (questionIndex < questions.length) renderPill('ask');
    else renderPill('done', doneText(lastResult));
}

async function saveQuestion(answer) {
    const value = clean(answer);
    if (!value) return renderPill('ask', 'Type an answer, or Skip');
    renderPill('busy', 'Saving…');
    const filled = await answerQuestion(questions[questionIndex], value);
    if (filled) { lastResult.filled++; lastResult.needYou = stillNeeded(); }
    nextQuestion();
}

async function fillFromPill() {
    renderPill('busy', 'Filling…');
    try {
        const reply = await browser.runtime.sendMessage({ type: 'applyProfile' });
        if (!reply || !reply.ok) throw new Error(reply ? reply.error : 'no reply');
        afterFill(await fillPage(reply.apply, (progress) => renderPill('busy', progress)));
    } catch (err) {
        renderPill('busy', `Couldn't fill: ${err.message || err}`);
    }
}

async function generateFromPill() {
    renderPill('busy', 'Making your CV…');
    const state = await generateCv().catch(() => 'failed');
    if (lastResult) { lastResult.cv = state; lastResult.needYou = stillNeeded(); }
    renderPill('done', doneText(lastResult || { filled: 0, cv: state }));
}

async function generateLetterFromPill() {
    renderPill('busy', 'Writing your cover letter…');
    const state = await generateLetter().catch(() => 'failed');
    if (lastResult) { lastResult.letter = state; lastResult.needYou = stillNeeded(); }
    renderPill('done', doneText(lastResult || { filled: 0, letter: state }));
}

function saveFile(base64, name) {
    const url = URL.createObjectURL(pdfFile(base64, name));
    const link = document.createElement('a');
    link.href = url;
    link.download = name;
    pillShadow.appendChild(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 60000);
}

async function markApplied(chance) {
    const title = clean(pillShadow.querySelector('[data-f="title"]').value);
    const company = clean(pillShadow.querySelector('[data-f="company"]').value);
    if (!title || !company) return renderPill('mark', 'Role and company are needed');
    job.title = title;
    job.company = company;
    renderPill('busy', 'Adding…');
    const reply = await browser.runtime.sendMessage({
        type: 'addApplication',
        job: {
            title, company, link: job.link, location: job.location, jd: job.jd, jobId: job.jobId || undefined,
            shortlistChance: chance === '' ? null : Number(chance),
            cv: job.cv && !job.jobId ? { name: job.cvName, pdf: job.cv } : undefined,
        },
    }).catch((err) => ({ ok: false, error: String(err.message || err) }));
    if (!reply || !reply.ok) return renderPill('mark', `Couldn't add: ${reply ? reply.error : 'no reply'}`);
    forgetJob();
    renderPill('added', reply.existed ? 'Already in Applied ✓' : 'Added to Applied ✓');
}

function onPillClick(event) {
    const button = event.target.closest('button');
    if (!button) return;
    const act = button.getAttribute('data-act');
    if (act === 'close') { pillDismissed = true; pillHost.remove(); }
    else if (act === 'fill') fillFromPill();
    else if (act === 'savecv') saveFile(job.cv, job.cvName);
    else if (act === 'saveletter') saveFile(job.letter.pdf, job.letter.fileName);
    else if (act === 'gencv') generateFromPill();
    else if (act === 'genletter') generateLetterFromPill();
    else if (act === 'mark') currentJob().then(() => renderPill('mark'));
    else if (act === 'chance') markApplied(button.getAttribute('data-n'));
    else if (act === 'option') saveQuestion(button.getAttribute('data-v'));
    else if (act === 'saveq') saveQuestion(pillShadow.querySelector('[data-f="answer"]').value);
    else if (act === 'skipq') nextQuestion();
}

async function checkForThanks() {
    if (pillHost || pillDismissed || !THANKS_WORDS.test(document.body ? document.body.innerText.slice(0, 20000) : '')) return;
    const stored = await pendingJob();
    if (!stored || pillHost) return;
    job = stored;
    renderPill('thanks', 'Sent it?');
}

function checkForForm() {
    if (pillHost || pillDismissed) return;
    try {
        if (looksLikeApplication()) renderPill('ready');
        else checkForThanks();
    } catch (e) { /* never break the page */ }
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
        return fillPage(message.apply)
            .then((res) => { afterFill(res); return res; })
            .catch((err) => ({ error: String(err.message || err) }));
    }
    return undefined;
});
