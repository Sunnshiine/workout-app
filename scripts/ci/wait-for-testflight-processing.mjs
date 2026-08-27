// Wait for an uploaded TestFlight build to finish App Store processing, and
// fail loudly with the build's actual state when it doesn't.
//
// This replaces wait-for-processing in apple-actions/upload-testflight-build,
// which mints one App Store Connect JWT when the step starts and reuses it for
// the whole poll. ASC tokens live ~10 minutes, and the action's backoff pushes
// later polls past that, so any build Apple is slow to surface dies as a bogus
// "401 NOT_AUTHORIZED" instead of a verdict (PR #505 build 49). Minting a
// fresh token per request removes the ceiling; polling processingState turns
// "never appeared" and "processing FAILED" into distinct, explained failures.
//
// A build Apple rejects during ingest (e.g. ITMS-90534, unsupported SDK) never
// becomes queryable at all — the visibility timeout here is that verdict, and
// the rejection detail only exists in the account's App Store Connect email.
//
// Env:
//   ASC_ISSUER_ID, ASC_KEY_ID, ASC_PRIVATE_KEY  App Store Connect API key
//   BUNDLE_ID        app bundle id, e.g. com.sunnypatel.WorkoutTracker[.dev]
//   BUILD_VERSION    the build's CFBundleVersion (its build number)
//   TIMEOUT_MINUTES  optional overall deadline, default 30

import crypto from 'node:crypto';

const {
  ASC_ISSUER_ID, ASC_KEY_ID, ASC_PRIVATE_KEY,
  BUNDLE_ID, BUILD_VERSION,
} = process.env;
const TIMEOUT_MINUTES = Number(process.env.TIMEOUT_MINUTES || 30);
const POLL_SECONDS = 30;

const die = (msg) => { console.error(msg); process.exit(1); };
for (const [k, v] of Object.entries({ ASC_ISSUER_ID, ASC_KEY_ID, ASC_PRIVATE_KEY, BUNDLE_ID, BUILD_VERSION })) {
  if (!v) die(`Missing required env ${k}`);
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

const API = 'https://api.appstoreconnect.apple.com';

async function api(path) {
  const res = await fetch(`${API}${path}`, {
    headers: { Authorization: `Bearer ${mintToken()}` },
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`GET ${path} → ${res.status}: ${text}`);
  return JSON.parse(text);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const apps = await api(`/v1/apps?filter[bundleId]=${encodeURIComponent(BUNDLE_ID)}&limit=1`);
const appId = apps.data?.[0]?.id;
if (!appId) die(`No app found for bundle id ${BUNDLE_ID}`);

const deadline = Date.now() + TIMEOUT_MINUTES * 60_000;
let lastState = null;
while (Date.now() < deadline) {
  let build;
  try {
    const builds = await api(
      `/v1/builds?filter[app]=${appId}&filter[version]=${encodeURIComponent(BUILD_VERSION)}` +
      '&fields[builds]=processingState,uploadedDate&limit=1');
    build = builds.data?.[0];
  } catch (e) {
    // Transient API errors must not kill a wait that is doing its job.
    console.log(`Poll error (will retry): ${e.message}`);
  }
  const state = build?.attributes?.processingState ?? 'NOT VISIBLE YET';
  if (state !== lastState) {
    console.log(`Build ${BUILD_VERSION}: ${state}`);
    lastState = state;
  }
  if (state === 'VALID') {
    console.log(`Build ${BUILD_VERSION} processed VALID.`);
    process.exit(0);
  }
  if (state === 'FAILED' || state === 'INVALID') {
    die(`Build ${BUILD_VERSION} finished processing as ${state}. ` +
      'App Store Connect shows the build with an error; the rejection email ' +
      'on the developer account has the ITMS detail.');
  }
  await sleep(POLL_SECONDS * 1000);
}

die(`Build ${BUILD_VERSION} did not surface in App Store Connect within ` +
  `${TIMEOUT_MINUTES} minutes of a committed upload. That pattern means Apple ` +
  'rejected the delivery during ingest (e.g. ITMS-90534, unsupported ' +
  'SDK/Xcode — check the App Store Connect email on the developer account), ' +
  'or processing is exceptionally slow — re-run this job to resume waiting.');
