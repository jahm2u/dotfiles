#!/usr/bin/env node
/**
 * geo-probe — fetch a URL from a country's residential exit and report what a real
 * visitor there receives. Reports status + BYTE SIZE + redirect chain, because on a
 * cloaked box a 200 is the block and a 302 is the pass.
 *
 * Run from the PRIMARY checkout (a worktree has no .env, so the key resolves empty).
 *   node probe.js --country gb [--control ca] --url '<url>'
 */

const path = require('path');

// This skill lives under ~/.claude/skills, which is a symlink into dotfiles — so node
// resolves modules from THERE, not from the repo. Every require must be absolute.
const REPO = process.env.BF_REPO || '/Users/v/repos/01_business/tp/BabaFlow';
require(path.join(REPO, 'node_modules/dotenv')).config({ path: path.join(REPO, '.env') });
const proxyService = require(path.join(REPO, 'src/services/proxy-service'));
// Requiring the package dir directly yields the ESM interop wrapper, whose callable
// export sits on .default — axios.get is undefined without this.
const axiosMod = require(path.join(REPO, 'node_modules/axios'));
const axios = axiosMod.default || axiosMod;
// axios's own `proxy:` option does NOT open a CONNECT tunnel for https targets — it
// forwards a plain request to port 443 and the origin answers
// "400 The plain HTTP request was sent to HTTPS port". Every https probe fails without
// an explicit tunnelling agent. (Same defect afflicts the app's fetchWithProxy.)
const { HttpsProxyAgent } = require(path.join(REPO, 'node_modules/https-proxy-agent'));

function arg(name) {
  const i = process.argv.indexOf(`--${name}`);
  return i > -1 ? process.argv[i + 1] : null;
}

const url = arg('url');
const country = arg('country');
const control = arg('control');
const timeout = Number(arg('timeout') || 20000);

if (!url || !country) {
  console.error("usage: probe.js --country <iso2> [--control <iso2>] --url '<url>' [--timeout ms]");
  process.exit(2);
}
if (!process.env.NODEMAVEN_API_KEY) {
  console.error('NODEMAVEN_API_KEY is empty. Are you in a worktree? A worktree has no .env — run from the primary checkout.');
  process.exit(2);
}

async function probe(cc) {
  const cfg = await proxyService.buildProxyConfig(cc);
  const { host, port, auth } = cfg.proxy;
  // Build the tunnel ourselves and DISABLE axios's own proxy handling (proxy:false),
  // or axios bypasses the agent and reintroduces the plain-request-to-443 failure.
  const agent = new HttpsProxyAgent(
    `http://${encodeURIComponent(auth.username)}:${encodeURIComponent(auth.password)}@${host}:${port}`
  );
  const tunnel = { httpAgent: agent, httpsAgent: agent, proxy: false };
  const hops = [];
  let current = url;
  let res;

  for (let i = 0; i < 10; i++) {
    res = await axios.get(current, {
      ...tunnel,
      timeout,
      maxRedirects: 0,
      // resolve on ANY status so a 3xx/4xx is data to compare, not an exception
      validateStatus: () => true,
      responseType: 'text',
      transformResponse: [(d) => d],
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml',
      },
    }).catch((e) => {
      if (e.response) { return e.response; }
      throw e;
    });

    const loc = res.headers && (res.headers.location || res.headers.Location);
    hops.push({ status: res.status, url: current, location: loc || null });
    if (res.status >= 300 && res.status < 400 && loc) {
      current = loc.startsWith('http') ? loc : new URL(loc, current).toString();
      continue;
    }
    break;
  }

  const body = typeof res.data === 'string' ? res.data : String(res.data || '');
  return {
    country: cc.toUpperCase(),
    status: res.status,
    bytes: Buffer.byteLength(body, 'utf8'),
    hops: hops.length,
    redirected: hops.length > 1 || (hops[0] && hops[0].status >= 300 && hops[0].status < 400),
    finalUrl: current,
    chain: hops.map((h) => `${h.status}${h.location ? ' -> ' + h.location.slice(0, 90) : ''}`),
  };
}

function report(r) {
  console.log(`\n[${r.country}]  status=${r.status}  bytes=${r.bytes}  hops=${r.hops}  redirected=${r.redirected}`);
  r.chain.forEach((c, i) => console.log(`   ${i + 1}. ${c}`));
  console.log(`   final: ${r.finalUrl.slice(0, 140)}`);
}

(async () => {
  // The exits 504 transiently on roughly half of requests, and the failure moves between
  // countries run to run — so a single attempt per exit is not a measurement. Retry until
  // the TARGET answers, and say how many attempts it took.
  const transient = (r) => r.bytes === 0 && [502, 503, 504, 407, 429].includes(r.status);
  const results = [];
  for (const cc of [country, control].filter(Boolean)) {
    let r = null;
    for (let attempt = 1; attempt <= 4; attempt++) {
      try {
        r = await probe(cc);
        if (!transient(r)) { r.attempts = attempt; break; }
        console.log(`[${cc.toUpperCase()}] attempt ${attempt}: proxy ${r.status}, retrying…`);
      } catch (e) {
        console.log(`[${cc.toUpperCase()}] attempt ${attempt}: ${e.message}, retrying…`);
      }
    }
    if (r) { results.push(r); report(r); }
    else { console.log(`\n[${cc.toUpperCase()}]  gave up after 4 attempts`); }
  }

  // A proxy-level failure is NOT a response from the target. Comparing one against a
  // real response manufactures a country difference that does not exist — the exact
  // false positive this instrument exists to avoid.
  const proxyFailed = (r) => r.bytes === 0 && [502, 503, 504, 407, 429].includes(r.status);
  const bad = results.filter(proxyFailed);
  if (bad.length > 0) {
    console.log('\n--- INCONCLUSIVE ---');
    bad.forEach((r) => console.log(`${r.country}: status ${r.status} with an EMPTY body = the PROXY failed, not the target.`));
    console.log('=> This is an instrument failure. Re-run that exit; do NOT read it as a country difference.');
    return;
  }

  if (results.length === 2) {
    const [a, b] = results;
    console.log('\n--- comparison ---');
    if (a.status === b.status && Math.abs(a.bytes - b.bytes) < 64) {
      console.log(`SAME response for ${a.country} and ${b.country} (status ${a.status}, ~${a.bytes}B).`);
      console.log('=> the COUNTRY IS NOT THE VARIABLE. Look elsewhere.');
    } else {
      console.log(`${a.country}: ${a.status}/${a.bytes}B redirected=${a.redirected}`);
      console.log(`${b.country}: ${b.status}/${b.bytes}B redirected=${b.redirected}`);
      console.log('=> responses DIFFER by country. On a cloaked box, 302=monetized, 200=safe page (hidden).');
    }
  } else if (results.length === 1) {
    console.log('\nNOTE: no control country was probed. One sample cannot show the country mattered.');
  }
  console.log('\nReminder: this probe carries no scid=, so it does not look like a real recipient hit in Apache logs.');
})();
