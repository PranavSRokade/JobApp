const details = document.getElementById('details');
const page = document.getElementById('page');
const fillButton = document.getElementById('fill');
const result = document.getElementById('result');
let apply = null;
let tabId = null;
let pageHasForm = false;

function show(el, text, bad = false) {
    el.textContent = text;
    el.classList.toggle('bad', bad);
}

function updateButton() {
    fillButton.disabled = !(apply && pageHasForm);
}

async function loadDetails() {
    const reply = await browser.runtime.sendMessage({ type: 'applyProfile' });
    if (!reply || !reply.ok) return show(details, `Couldn't load (${reply ? reply.error : 'no reply'})`, true);
    apply = reply.apply;
    const name = `${apply.firstName} ${apply.lastName}`.trim();
    show(details, name || 'Not filled in yet', !name);
    updateButton();
}

async function scanPage() {
    const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
    tabId = tab.id;
    try {
        const reply = await browser.tabs.sendMessage(tabId, { type: 'scan' });
        if (reply) {
            pageHasForm = true;
            show(page, `${reply.fields} fields on ${reply.host}`);
            return updateButton();
        }
    } catch (e) { /* the page script isn't allowed on this site yet */ }
    show(page, 'No form here, or JobFill isn’t allowed on this site', true);
}

fillButton.addEventListener('click', async () => {
    fillButton.disabled = true;
    fillButton.textContent = 'Filling…';
    try {
        const reply = await browser.tabs.sendMessage(tabId, { type: 'fill', apply });
        if (!reply || reply.error) {
            result.textContent = `Couldn't fill: ${reply ? reply.error : 'the page didn’t answer'}`;
        } else {
            const need = reply.needYou
                ? ` <strong>${reply.needYou}</strong> required ${reply.needYou === 1 ? 'field needs' : 'fields need'} you (orange dashes).`
                : ' Nothing required is left empty.';
            result.innerHTML = `Filled <strong>${reply.filled}</strong> of ${reply.fields} (purple outline).${need} Check everything before you submit.`;
        }
    } catch (e) {
        result.textContent = `Couldn't fill: ${e.message || e}`;
    }
    fillButton.textContent = 'Fill this page';
    updateButton();
});

loadDetails();
scanPage();
