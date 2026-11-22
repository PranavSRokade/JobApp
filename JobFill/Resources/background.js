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
    return undefined;
});
