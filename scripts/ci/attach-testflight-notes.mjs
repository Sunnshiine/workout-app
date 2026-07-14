// Best-effort: attach a "What to Test" note to a build that is already uploaded
// to TestFlight and processed VALID.
//
// The upload step (apple-actions/upload-testflight-build) no longer sets
// release-notes itself: when given release-notes it polls App Store Connect for
// the build's beta localization record and writes the note there, but that
// record lags ~10 min on the first builds of a brand-new app, so the action
// exhausts its fixed 20×30s poll and fails an upload that actually succeeded.
// The action exposes no knob to make that write non-fatal, so we do it here
// under continue-on-error instead: a slow or missing localization record never
// red-Xes the pipeline, because the binary is already on TestFlight and VALID.
//
// Env:
//   ASC_ISSUER_ID, ASC_KEY_ID, ASC_PRIVATE_KEY  App Store Connect API key
//   BUNDLE_ID       app bundle id, e.g. com.sunnypatel.WorkoutTracker[.dev]
//   BUILD_VERSION   the build's CFBundleVersion (its build number)
//   WHAT_TO_TEST    note body (empty → nothing to do)
//   LOCALE          optional beta-localization locale, default en-US

import crypto from 'node:crypto';

const {
  ASC_ISSUER_ID, ASC_KEY_ID, ASC_PRIVATE_KEY,
  BUNDLE_ID, BUILD_VERSION, WHAT_TO_TEST,
} = process.env;
const LOCALE = process.env.LOCALE || 'en-US';

const die = (msg) => { console.error(msg); process.exit(1); };
for (const [k, v] of Object.entries({ ASC_ISSUER_ID, ASC_KEY_ID, ASC_PRIVATE_KEY, BUNDLE_ID, BUILD_VERSION })) {
  if (!v) die(`Missing required env ${k}`);
}
if (!WHAT_TO_TEST || !WHAT_TO_TEST.trim()) {
  console.log('No WHAT_TO_TEST content; nothing to attach.');
  process.exit(0);
}

const b64url = (buf) => Buffer.from(buf).toString('base64url');

// ES256 JWT for the App Store Connect API. Node's crypto signs with the EC key
// directly; dsaEncoding ieee-p1363 produces the raw R||S JOSE signature ASC
// requires (the default DER encoding would be rejected).
function mintToken() {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'ES256', kid: ASC_KEY_ID, typ: 'JWT' };
  const payload = { iss: ASC_ISSUER_ID, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' };
  const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
  const sig = crypto.sign('SHA256', Buffer.from(signingInput), { key: ASC_PRIVATE_KEY, dsaEncoding: 'ieee-p1363' });
  return `${signingInput}.${b64url(sig)}`;
}

const token = mintToken();
const API = 'https://api.appstoreconnect.apple.com';

async function api(method, path, body) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${path} → ${res.status}: ${text}`);
  return text ? JSON.parse(text) : {};
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// 1. Resolve the app id from the bundle id.
const apps = await api('GET', `/v1/apps?filter[bundleId]=${encodeURIComponent(BUNDLE_ID)}&limit=1`);
const appId = apps.data?.[0]?.id;
if (!appId) die(`No app found for bundle id ${BUNDLE_ID}`);

// 2. Find the freshly uploaded build by its CFBundleVersion. It processed VALID
//    already, but ASC can briefly lag before it is queryable — retry a little.
let buildId;
for (let attempt = 1; attempt <= 6 && !buildId; attempt++) {
  const builds = await api('GET', `/v1/builds?filter[app]=${appId}&filter[version]=${encodeURIComponent(BUILD_VERSION)}&limit=1`);
  buildId = builds.data?.[0]?.id;
  if (!buildId && attempt < 6) {
    console.log(`Build ${BUILD_VERSION} not queryable yet (attempt ${attempt}/6); retrying in 20s`);
    await sleep(20000);
  }
}
if (!buildId) die(`Build ${BUILD_VERSION} not found for ${BUNDLE_ID} after retries`);

// 3. Upsert the beta build localization for the locale.
const locs = await api('GET', `/v1/builds/${buildId}/betaBuildLocalizations`);
const existing = locs.data?.find((l) => l.attributes?.locale === LOCALE);
if (existing) {
  await api('PATCH', `/v1/betaBuildLocalizations/${existing.id}`, {
    data: { type: 'betaBuildLocalizations', id: existing.id, attributes: { whatsNew: WHAT_TO_TEST } },
  });
  console.log(`Updated "What to Test" on build ${BUILD_VERSION} (${LOCALE}).`);
} else {
  await api('POST', '/v1/betaBuildLocalizations', {
    data: {
      type: 'betaBuildLocalizations',
      attributes: { locale: LOCALE, whatsNew: WHAT_TO_TEST },
      relationships: { build: { data: { type: 'builds', id: buildId } } },
    },
  });
  console.log(`Created "What to Test" on build ${BUILD_VERSION} (${LOCALE}).`);
}
