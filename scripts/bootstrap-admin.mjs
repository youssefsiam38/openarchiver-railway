// openarchiver-railway administrator bootstrap.
//
// Open Archiver's setup endpoint creates the first Super Admin and refuses to run once any user
// exists, which is the right design. The gap it leaves is timing: on a platform that publishes a
// domain the moment the service starts, whoever reaches /setup first owns an archive of an entire
// organisation's mail. This runs against the backend on loopback, before the public port opens.
//
// Idempotent: if setup is already complete it reports that and exits. Values are never printed;
// only names, lengths and outcomes.

const base = process.env.OPENARCHIVER_BACKEND_URL;
const email = process.env.OPENARCHIVER_ADMIN_EMAIL ?? '';
const password = process.env.OPENARCHIVER_ADMIN_PASSWORD ?? '';
const firstName = process.env.OPENARCHIVER_ADMIN_FIRST_NAME || 'Archive';
const lastName = process.env.OPENARCHIVER_ADMIN_LAST_NAME || 'Administrator';

const log = (msg) => console.error(`[openarchiver-railway] ${msg}`);
const fail = (msg) => {
  log(`FATAL: ${msg}`);
  process.exit(1);
};

if (!base) fail('OPENARCHIVER_BACKEND_URL is not set');
if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) fail('OPENARCHIVER_ADMIN_EMAIL must be an e-mail address');
if (password.length < 12) fail('OPENARCHIVER_ADMIN_PASSWORD must be at least 12 characters');

const root = base.replace(/\/$/, '');

const statusRes = await fetch(`${root}/v1/auth/status`).catch((err) =>
  fail(`could not reach the backend on loopback: ${err.message}`)
);
if (!statusRes.ok) fail(`setup status returned HTTP ${statusRes.status}`);
const status = await statusRes.json().catch(() => ({}));

if (status?.needsSetup === false) {
  log('administrator bootstrap skipped: setup is already complete; OPENARCHIVER_ADMIN_PASSWORD is now stale and is ignored');
  process.exit(0);
}

const res = await fetch(`${root}/v1/auth/setup`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ email, password, first_name: firstName, last_name: lastName })
}).catch((err) => fail(`setup request failed: ${err.message}`));

if (res.status === 201) {
  log(`administrator bootstrap complete: created the Super Admin (password length ${password.length})`);
  process.exit(0);
}

let body = {};
try {
  body = await res.json();
} catch {
  /* a non-JSON body is reported through the status below */
}
const message = String(body?.message ?? '').toLowerCase();
if (res.status === 403 && message.includes('already been completed')) {
  log('administrator bootstrap skipped: setup was completed by someone else first');
  process.exit(0);
}

fail(`setup failed with HTTP ${res.status}${message ? `: ${message}` : ''}`);
