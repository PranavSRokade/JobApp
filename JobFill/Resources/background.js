// Talks to the job worker for the popup and the page script. The worker wants the app key, which
// lives in the app (Secrets.swift), so it is fetched once from the native side and kept in memory.
const WORKER = 'https://job-worker.pranavrokade.workers.dev';
const PROFILE = 'spencer';
let appKey = null;

async function getKey() {
    if (appKey) return appKey;
    const reply = await browser.runtime.sendNativeMessage('com.spencer.JobApp', { type: 'appKey' });
    if (!reply || !reply.key) throw new Error('The app did not hand over its key');
    appKey = reply.key;
    return appKey;
}

async function worker(path, options = {}) {
    const headers = { ...(options.headers || {}), 'X-App-Key': await getKey() };
    const res = await fetch(`${WORKER}${path}`, { ...options, headers });
    if (!res.ok) throw new Error(`Worker answered ${res.status}`);
    return res.json();
}

function post(path, body) {
    return worker(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
}

browser.runtime.onMessage.addListener((message) => {
    if (message && message.type === 'applyProfile') {
        return worker(`/api/profile/apply?profile=${PROFILE}`)
            .then((body) => ({ ok: true, apply: body.apply }))
            .catch((err) => ({ ok: false, error: String(err.message || err) }));
    }
    if (message && message.type === 'matchLabels') {
        return worker('/api/apply/match', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ fields: message.fields, profile: PROFILE }),
        })
            .then((body) => ({ ok: true, keys: body.keys }))
            .catch((err) => ({ ok: false, error: String(err.message || err) }));
    }
    if (message && message.type === 'answer') {
        return post('/api/answer', {
            jd: message.jd, company: message.company, title: message.title, question: message.question,
            latex: message.latex || null, profile: PROFILE,
        })
            .then((body) => ({ ok: true, text: body.text }))
            .catch((err) => ({ ok: false, error: String(err.message || err) }));
    }
    if (message && message.type === 'cv') {
        return post('/api/cv', { jd: message.jd, profile: PROFILE })
            .then((body) => ({ ok: true, pdf: body.pdf, latex: body.latex }))
            .catch((err) => ({ ok: false, error: String(err.message || err) }));
    }
    if (message && message.type === 'preparedCv') {
        const query = new URLSearchParams({ profile: PROFILE, company: message.company || '', context: message.context || '' });
        return worker(`/api/prepared-cv/match?${query}`)
            .then((body) => ({ ok: true, match: body.match, pdf: body.pdf, latex: body.latex, letter: body.letter }))
            .catch((err) => ({ ok: false, error: String(err.message || err) }));
    }
    if (message && message.type === 'saveAnswer') {
        return post(`/api/profile/apply/answer?profile=${PROFILE}`, { question: message.question, answer: message.answer })
            .then((body) => ({ ok: true, apply: body.apply }))
            .catch((err) => ({ ok: false, error: String(err.message || err) }));
    }
    if (message && message.type === 'coverLetter') {
        return post('/api/cover-letter', { jd: message.jd, latex: message.latex || null, profile: PROFILE })
            .then((body) => ({ ok: true, pdf: body.pdf, text: body.text }))
            .catch((err) => ({ ok: false, error: String(err.message || err) }));
    }
    if (message && message.type === 'addApplication') {
        return post(`/api/applications/add?profile=${PROFILE}`, message.job)
            .then((body) => ({ ok: true, existed: body.existed }))
            .catch((err) => ({ ok: false, error: String(err.message || err) }));
    }
    return undefined;
});
