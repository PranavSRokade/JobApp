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
            const drafted = reply.drafted ? ` <strong>${reply.drafted}</strong> ${reply.drafted === 1 ? 'answer' : 'answers'} drafted (purple dashes): read before sending.` : '';
            const cv = {
                attached: ' Your JobApp CV for this job is attached.',
                save: ' The CV field wouldn’t take the file: use Save CV on the page.',
                none: ' No CV made for this job in JobApp: tap Generate CV on the page.',
            }[reply.cv] || '';
            const letter = {
                attached: ' Your JobApp cover letter is attached.',
                save: ' The letter field wouldn’t take the file: use Save letter on the page.',
                none: ' No cover letter made for this job: tap Generate letter on the page.',
            }[reply.letter] || '';
            const asks = reply.questions ? ` <strong>${reply.questions}</strong> ${reply.questions === 1 ? 'question waits' : 'questions wait'} for you on the page.` : '';
            result.innerHTML = `Filled <strong>${reply.filled}</strong> of ${reply.fields} (purple outline).${drafted}${cv}${letter}${asks}${need} After you submit, tap Mark applied on the page.`;
        }
    } catch (e) {
        result.textContent = `Couldn't fill: ${e.message || e}`;
    }
    fillButton.textContent = 'Fill this page';
    updateButton();
});

loadDetails();
scanPage();
