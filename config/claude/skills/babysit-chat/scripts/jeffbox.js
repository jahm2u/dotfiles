'use strict';
/**
 * JEFF BOX — operator presence in a partner Telegram chat.
 *
 * A human-driven Claude session sits in a partner's Telegram channel, reads what
 * the operators are actually saying, and answers them directly — fixing what can
 * be fixed now instead of filing a ticket and waiting for the dev pipeline.
 *
 * Two verbs, both run LOCALLY (no prod SSH required for `say`):
 *
 *   node scripts/jeffbox.js tail --org PD [--interval 30] [--since ISO] [--once]
 *       Polls CT212's inbound message cache and prints ONE LINE per new message.
 *       Designed as the command for a persistent Monitor: each line becomes an
 *       event, so the session is woken by chat traffic instead of polling itself.
 *
 *   node scripts/jeffbox.js say --org PD --text "..." [--reply MSG_ID]
 *                               [--topic general|inbox|alerts] [--raw] [--dry-run]
 *       Posts into the org's chat through the reporter bot and prints the
 *       Telegram `message_id`. That id is the ONLY proof of delivery.
 *
 * ---------------------------------------------------------------------------
 * Why the details below are not incidental
 * ---------------------------------------------------------------------------
 *
 * 1. THE `JEFF BOX` PREFIX IS MANDATORY (auto-prepended unless --raw).
 *    The reporter bot shares `BABA_TELEGRAM_BOT_TOKEN` with Baba, so our messages
 *    arrive from the same @bf_baba_bot account that posts Baba's autonomous
 *    replies. Without a marker the operators cannot tell an automated Baba answer
 *    from a human-driven session speaking for Jeff. Normal case — the original
 *    ALL-CAPS convention was retired 2026-08-14.
 *
 * 2. `NODE_ENV=production` IS FORCED for `say`.
 *    telegram-config dev-redirects sendMessage to DEV_CHAT_ID when NODE_ENV is
 *    'development', where @bf_baba_bot gets "chat not found" — the send fails
 *    cleanly and nothing reaches the partner. Local `.env` already carries the
 *    real token and points DB_HOST at prod, so production mode here is correct
 *    and is what makes the whole loop runnable from a laptop.
 *
 * 3. WE CALL `bot.sendMessage` DIRECTLY, NOT `sendToOrg`.
 *    `sendToOrg` returns `{ok:true}` carrying no message_id, and swallows send
 *    errors into a log line — it reports success for messages that never left.
 *    `prod.sh notify send` is worse: it is additionally preference-gated and no
 *    org user has opted into telegram for these source types, so it delivers
 *    nothing while printing success:true. Only a returned message_id is proof.
 *
 *    That proof is forgeable, which is why `assertRealBot` exists. With no
 *    `BABA_TELEGRAM_BOT_TOKEN` in the environment, telegram-config hands out a
 *    stub bot whose `sendMessage` resolves `{message_id: 1}` — a truthy id from
 *    a send that never happened. Every delivery claim this tool makes rests on
 *    refusing to run against that stub.
 *
 * 4. NO `parse_mode` BY DEFAULT.
 *    Operator-facing prose is full of underscores, asterisks and stray brackets
 *    from campaign and server names. Markdown parsing turns those into a 400 and
 *    a formatting fallback nobody asked for. Plain text always delivers.
 *
 * 5. THE TAIL IS INBOUND-ONLY.
 *    `message_cache.db` on CT212 caches messages the bot RECEIVED. Our own sends
 *    never appear there, so never confirm a send by reading the tail back.
 *
 * 6. FATAL ERRORS GO TO STDOUT, PREFIXED `[jeffbox] WARNING`.
 *    A monitor's stderr is routinely redirected away. An error that only reaches
 *    stderr makes a dead tail look exactly like a quiet channel — the single
 *    failure this tool most needs to never have.
 */

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

/**
 * Locate the BabaFlow checkout.
 *
 * This script lives with the skill, not in the repo, but it borrows the app's
 * own db and telegram config so it talks to the same prod DB and the same bot
 * the platform does. Resolution order: an explicit BABAFLOW_REPO, then the
 * current working directory (so it works from any worktree), then the usual
 * checkout. It throws a named error rather than letting a bare MODULE_NOT_FOUND
 * surface, because that error reads as a broken script rather than a wrong cwd.
 */
function findRepo() {
  const candidates = [
    process.env.BABAFLOW_REPO,
    process.cwd(),
    '/Users/v/repos/01_business/tp/BabaFlow'
  ].filter(Boolean);
  for (const dir of candidates) {
    try {
      require.resolve(path.join(dir, 'src/config/db-config'));
      return dir;
    } catch { /* try the next candidate */ }
  }
  throw new Error(
    'Cannot find a BabaFlow checkout (looked for src/config/db-config in '
    + `${candidates.join(', ')}) — run from the repo or set BABAFLOW_REPO`
  );
}

const REPO = findRepo();

// CT212 (Baba) holds the rolling inbound cache. Route: laptop -> mox -> pct exec.
const CACHE_DB = '/opt/babaflow/data/message_cache.db';
const MOX_HOST = process.env.JEFFBOX_MOX_HOST || 'mox';
const BABA_CT = process.env.JEFFBOX_BABA_CT || '212';

/** Prefix that survives `2>/dev/null` on the monitor command line. */
const WARN = '[jeffbox] WARNING';

// ---------------------------------------------------------------------------
// arg parsing
// ---------------------------------------------------------------------------

/**
 * Parse `--flag value` / `--flag` pairs.
 *
 * `--` ends flag parsing, so a message that begins with a dash can still be
 * passed: `say --org PD -- "--- status ---"`. Without that escape a legitimate
 * message is silently swallowed as a flag name.
 */
function parseArgs(argv) {
  const out = { _: [] };
  let literal = false;
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (!literal && a === '--') {
      literal = true;
    } else if (!literal && a.startsWith('--')) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next === undefined || (next.startsWith('--') && next !== '--')) {
        out[key] = true;
      } else {
        out[key] = next;
        i += 1;
      }
    } else {
      out._.push(a);
    }
  }
  return out;
}

/**
 * Poll interval in ms.
 *
 * `Number('30s')` is NaN and `setTimeout(fn, NaN)` fires in ~1ms, which turns a
 * typo into an unbounded stream of ssh processes with nothing printed to say so.
 */
function parseInterval(raw) {
  if (raw === undefined || raw === true) return 30000;
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) {
    throw new Error(`--interval must be a positive number of seconds, got "${raw}"`);
  }
  return n * 1000;
}

/**
 * Starting cursor for the tail.
 *
 * Default is "now": a monitor reports what happens from the moment it is armed,
 * not a replay of whatever the cache happens to hold.
 *
 * A timezone is REQUIRED on an explicit value. `new Date('2026-08-25 09:00')`
 * parses as LOCAL time and then converts, so an operator west of UTC asking for
 * the last few hours silently skips them — and the only hint is a banner that
 * the documented monitor invocation redirects away.
 */
function parseSince(raw) {
  if (raw === undefined || raw === true) return new Date().toISOString();
  const value = String(raw);
  if (!/(Z|[+-]\d{2}:?\d{2})$/.test(value)) {
    throw new Error(
      `--since needs an explicit timezone, got "${value}" — use e.g. 2026-08-25T09:00:00Z, `
      + 'otherwise it is read as local time and silently shifts the window'
    );
  }
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) {
    throw new Error(`--since is not a parseable date: "${value}"`);
  }
  return d.toISOString();
}

// ---------------------------------------------------------------------------
// org lookup (prod DB via the repo's own pool — .env points at prod)
// ---------------------------------------------------------------------------

/**
 * Require a module with its console.log banner diverted to stderr.
 *
 * db-config and telegram-config both announce themselves on stdout at load.
 * In `tail` mode stdout IS the event stream, so those banners would arrive as
 * chat notifications. They are still worth seeing, so divert rather than discard.
 */
function requireQuietly(modulePath) {
  const realLog = console.log;
  console.log = (...a) => process.stderr.write(`${a.join(' ')}\n`);
  try {
    return require(modulePath);
  } finally {
    console.log = realLog;
  }
}

async function loadOrg(nameOrId) {
  const pool = requireQuietly(path.join(REPO, 'src/config/db-config'));
  const db = pool.promise();
  const byId = /^\d+$/.test(String(nameOrId));
  const [rows] = await db.query(
    `SELECT id, name, telegram_chat_id, telegram_topics
       FROM organizations
      WHERE ${byId ? 'id = ?' : 'name = ?'}
      LIMIT 1`,
    [byId ? Number(nameOrId) : String(nameOrId)]
  );
  if (!rows.length) throw new Error(`No organization matches "${nameOrId}"`);
  const org = rows[0];
  if (!org.telegram_chat_id) {
    throw new Error(`Org ${org.name} (${org.id}) has no telegram_chat_id — it has no chat to sit in`);
  }
  return org;
}

/**
 * Resolve a topic name to a Telegram `message_thread_id`.
 *
 * Only the literal `general` may resolve to null — that is the group's
 * unthreaded area, where the operators actually talk. Any other name that does
 * not resolve THROWS rather than falling back to General: a silent fallback
 * posts the message somewhere the operator did not ask for and then reports a
 * real message_id for it, which is affirmative proof of delivery to the wrong
 * place.
 */
function resolveTopicId(org, topic) {
  if (!topic || topic === 'general') return null;
  if (topic === true) {
    throw new Error('--topic needs a value (general, inbox, alerts, ...)');
  }
  let topics = org.telegram_topics;
  if (typeof topics === 'string') {
    try { topics = JSON.parse(topics); } catch { topics = null; }
  }
  const id = topics && topics[topic];
  if (!id) {
    const known = topics
      ? Object.keys(topics).filter((k) => topics[k]).concat('general').join(', ')
      : 'general';
    throw new Error(`Org ${org.name} has no "${topic}" topic — known topics: ${known}`);
  }
  return Number(id);
}

// ---------------------------------------------------------------------------
// tail — poll CT212's inbound cache, one stdout line per new message
// ---------------------------------------------------------------------------

/**
 * Build the node program that runs INSIDE CT212 and emits one JSON object per
 * line. It is shipped base64-encoded: the payload is then pure [A-Za-z0-9+/=],
 * which survives the ssh -> pct exec -> bash -lc quoting chain intact. Hand-
 * quoting the JS through three shells is how this kind of script acquires
 * silent, intermittent syntax errors.
 *
 * The comparison is `>=`, not `>`. `created_at` is a millisecond ISO string, so
 * two messages can share one; with `>` the second is skipped forever the moment
 * the first advances the cursor. `>=` re-fetches the boundary row each poll and
 * `seen` discards the duplicate — which is the job `seen` is named for and,
 * under `>`, could never actually do.
 */
function buildRemoteProgram(orgId, sinceIso) {
  return `
const db = require('better-sqlite3')(${JSON.stringify(CACHE_DB)}, { readonly: true });
const rows = db.prepare(
  "SELECT id, created_at, sender_name, org_id, topic_id, telegram_message_id, message_text " +
  "FROM message_cache WHERE org_id = ? AND created_at >= ? ORDER BY created_at ASC"
).all(${JSON.stringify(String(orgId))}, ${JSON.stringify(sinceIso)});
for (const r of rows) process.stdout.write(JSON.stringify(r) + '\\n');
`;
}

function runRemote(program) {
  const b64 = Buffer.from(program, 'utf8').toString('base64');
  const inner = `cd /opt/babaflow && echo ${b64} | base64 -d | node`;
  const remote = `pct exec ${BABA_CT} -- bash -lc '${inner}'`;
  return new Promise((resolve) => {
    const child = spawn('ssh', [MOX_HOST, remote], { stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    // Decode as a stream: a multi-byte character straddling a chunk boundary is
    // otherwise decoded as replacement characters.
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', (d) => { stdout += d; });
    child.stderr.on('data', (d) => { stderr += d; });
    // A transient ssh failure must not kill a persistent monitor — report and
    // let the caller keep polling.
    child.on('error', (err) => resolve({ code: -1, stdout: '', stderr: String(err.message) }));
    child.on('close', (code) => resolve({ code, stdout, stderr }));
  });
}

/** Collapse a message to a single line: one stdout line = one Monitor event. */
function formatEvent(row) {
  const when = String(row.created_at || '').slice(11, 19);
  const text = String(row.message_text || '')
    .replace(/\s*\n\s*/g, ' / ')
    .trim();
  const topic = row.topic_id && String(row.topic_id) !== '0' ? ` t${row.topic_id}` : '';
  return `[${when}Z]${topic} ${row.sender_name} #${row.telegram_message_id}: ${text}`;
}

/**
 * Bounded id memory for `>=` dedupe.
 *
 * Only the rows sharing the cursor timestamp can ever repeat, so the working
 * set is tiny — but a persistent monitor runs for the length of a session, and
 * an unbounded Set is a slow leak for no benefit.
 */
function createSeen(limit = 2000) {
  const set = new Set();
  const order = [];
  return {
    has: (id) => set.has(id),
    add(id) {
      if (set.has(id)) return;
      set.add(id);
      order.push(id);
      while (order.length > limit) set.delete(order.shift());
    },
    get size() { return set.size; }
  };
}

async function cmdTail(args) {
  const intervalMs = parseInterval(args.interval);
  let cursor = parseSince(args.since);
  const org = await loadOrg(args.org || args.o);

  const seen = createSeen();

  process.stderr.write(
    `[jeffbox] tailing ${org.name} (org ${org.id}, chat ${org.telegram_chat_id}) from ${cursor}\n`
  );

  let consecutiveFailures = 0;

  for (;;) {
    const res = await runRemote(buildRemoteProgram(org.id, cursor));

    if (res.code !== 0) {
      const detail = String(res.stderr).trim().split('\n').pop() || `exit ${res.code}`;
      // A one-shot read has no later poll to recover in, and the skill opens
      // with exactly that command to read the backlog. Reporting nothing and
      // exiting 0 would read as "the channel has been quiet".
      if (args.once) {
        throw new Error(`could not reach the ${org.name} message cache: ${detail}`);
      }
      consecutiveFailures += 1;
      // Stay quiet on a blip; speak up once the path looks genuinely down,
      // because a silent monitor is indistinguishable from a quiet chat.
      if (consecutiveFailures === 3) {
        console.log(`${WARN}: cannot reach the ${org.name} message cache (3 consecutive failures): ${detail}`);
      }
    } else {
      if (consecutiveFailures >= 3) {
        console.log(`${WARN}: reconnected to the ${org.name} message cache`);
      }
      consecutiveFailures = 0;
      for (const line of res.stdout.split('\n')) {
        const trimmed = line.trim();
        if (!trimmed.startsWith('{')) continue;
        let row;
        try { row = JSON.parse(trimmed); } catch { continue; }
        if (seen.has(row.id)) continue;
        seen.add(row.id);
        if (row.created_at > cursor) cursor = row.created_at;
        console.log(formatEvent(row));
      }
    }

    if (args.once) return;
    await new Promise((r) => setTimeout(r, intervalMs));
  }
}

// ---------------------------------------------------------------------------
// say — post as JEFF BOX, print the message_id
// ---------------------------------------------------------------------------

const PREFIX = 'JEFF BOX';

/**
 * Compose the outgoing message body.
 *
 * The prefix is applied HERE, on the only path that reaches sendMessage, rather
 * than left to the caller to remember. Our messages leave the same
 * @bf_baba_bot account that posts Baba's automated replies, so an unmarked
 * message is indistinguishable from one — and the operator acts on it as if a
 * bot said it.
 *
 * @param {string} text - operator-facing message
 * @param {boolean} raw - true to suppress the prefix
 * @returns {string}
 */
function composeBody(text, raw) {
  return raw ? String(text) : `${PREFIX}\n\n${String(text)}`;
}

/**
 * Telegram's sendMessage cap. 4096 UTF-16 code units, not bytes and not
 * codepoints — which is what `String.length` counts, so length comparisons
 * here are already in the right unit.
 */
const TG_LIMIT = 4096;

/**
 * Headroom for the " (1/3)" continuation marker appended to each part.
 * Deliberately generous: a wrong guess here fails the send at the API with a
 * message about entity length that reads nothing like "your text was too long".
 */
const MARKER_ROOM = 16;

/**
 * Split a composed body into Telegram-sized parts.
 *
 * Over-length was previously an unhandled case: the API rejects the whole
 * send, and since a failed send is the one outcome this tool exists to make
 * visible, a long message became an error at exactly the moment an operator
 * was waiting on it.
 *
 * Splitting prefers the coarsest boundary that fits, because where a message
 * breaks changes how it reads: paragraph, then line, then a hard character
 * cut for the pathological case of a single enormous line. A hard cut is
 * always wrong-looking, so it is the last resort rather than the algorithm.
 *
 * Parts are marked "(n/total)" so a reader can tell a multi-part message from
 * two unrelated ones — and, more importantly, can tell that the message they
 * are reading is not the whole message.
 *
 * @param {string} body the fully composed body, prefix included
 * @param {number} [limit] override for tests
 * @returns {string[]} one or more parts, each within the limit
 */
function splitForTelegram(body, limit = TG_LIMIT) {
  const text = String(body);
  if (text.length <= limit) return [text];

  const room = limit - MARKER_ROOM;
  const parts = [];
  let rest = text;

  while (rest.length > room) {
    // Coarsest boundary first. lastIndexOf searches within the window, so each
    // candidate is by construction a break that fits.
    const window = rest.slice(0, room);
    let cut = window.lastIndexOf('\n\n');
    if (cut < room * 0.5) cut = window.lastIndexOf('\n');
    if (cut < room * 0.5) cut = window.lastIndexOf(' ');
    if (cut <= 0) cut = room;             // one enormous unbroken line
    parts.push(rest.slice(0, cut).replace(/\s+$/, ''));
    rest = rest.slice(cut).replace(/^\s+/, '');
  }
  if (rest) parts.push(rest);

  const total = parts.length;
  return parts.map((p, i) => `${p}\n\n(${i + 1}/${total})`);
}

/**
 * Refuse to run against telegram-config's stub bot.
 *
 * With no `BABA_TELEGRAM_BOT_TOKEN`, telegram-config exports a stub whose
 * `sendMessage` resolves `{message_id: 1}` so that importing the module never
 * throws and unrelated sends degrade quietly. For this tool that default is
 * exactly wrong: it manufactures the one value we treat as proof of delivery.
 *
 * `isNoopBot` is a BOOLEAN (`!token`), not a predicate — calling it, or testing
 * `typeof === 'function'`, silently evaluates to false and leaves the stub in
 * place. `bot` is always truthy for the same reason, so it cannot be the test
 * either.
 *
 * @param {{bot: object, isNoopBot: boolean}} config
 */
function assertRealBot(config) {
  if (!config || !config.bot || config.isNoopBot) {
    throw new Error(
      'Telegram bot is a no-op stub (BABA_TELEGRAM_BOT_TOKEN missing) — it would '
      + 'resolve a fake message_id without sending. Load the app .env first.'
    );
  }
}

/**
 * Resolve the message body from --text, --file, or a positional argument.
 *
 * `--file` exists because a long message as an inline `--text` argument is a
 * multi-KB shell command, and agent harnesses routinely refuse to run one on
 * length/shape alone. That refusal is indistinguishable from a delivery
 * failure at the point of use, and the operator waiting in the channel just
 * sees silence. Reading from a file keeps the command line short however long
 * the message is.
 *
 * `--file -` reads stdin, so a heredoc works too.
 *
 * --text wins if both are given, rather than concatenating or erroring: a
 * stale message file left in a scratch directory must never be able to change
 * what an explicit --text sends.
 *
 * @param {object} args parsed CLI args
 * @returns {string} the message body
 */
function resolveText(args) {
  const inline = args.text !== undefined && args.text !== true ? args.text : undefined;
  if (inline) return inline;

  const file = args.file !== undefined && args.file !== true ? args.file : undefined;
  if (file) {
    const body = file === '-'
      ? fs.readFileSync(0, 'utf8')
      : fs.readFileSync(file, 'utf8');
    // Trailing newlines from an editor or heredoc are not part of the message,
    // but interior blank lines are load-bearing paragraph breaks.
    const trimmed = body.replace(/\s+$/, '');
    if (!trimmed) throw new Error(`say --file ${file} is empty — refusing to send a blank message`);
    return trimmed;
  }

  return args._[0];
}

async function cmdSay(args) {
  const text = resolveText(args);
  if (!text) {
    throw new Error(
      'say needs --text "..." or --file <path> (use `--file -` for stdin, '
      + 'or `--` before a message starting with a dash)'
    );
  }

  // Forced before telegram-config is required: the dev redirect is decided at
  // module load, so setting it afterwards would be a no-op that silently
  // swallows the message.
  process.env.NODE_ENV = 'production';

  const org = await loadOrg(args.org || args.o);
  const topicId = resolveTopicId(org, args.topic || 'general');

  const body = composeBody(text, Boolean(args.raw));

  const opts = {};
  if (topicId) opts.message_thread_id = topicId;
  if (args.reply && args.reply !== true) {
    const replyTo = Number(args.reply);
    if (!Number.isInteger(replyTo) || replyTo <= 0) {
      throw new Error(`--reply must be a Telegram message id, got "${args.reply}"`);
    }
    opts.reply_to_message_id = replyTo;
    // Without this a reply to a message that has since been deleted fails the
    // whole send rather than posting unthreaded.
    opts.allow_sending_without_reply = true;
  }

  if (args['dry-run']) {
    console.log(JSON.stringify({ dryRun: true, org: org.name, chat_id: org.telegram_chat_id, opts, body }, null, 2));
    return;
  }

  const config = requireQuietly(path.join(REPO, 'src/config/telegram-config'));
  assertRealBot(config);

  const parts = splitForTelegram(body);
  const ids = [];
  for (let i = 0; i < parts.length; i += 1) {
    // Only the FIRST part threads onto --reply. Replying every part to the same
    // message renders them as sibling replies in no guaranteed order, which is
    // exactly wrong for text that was split because it is sequential.
    const partOpts = i === 0 ? opts : { ...opts, reply_to_message_id: undefined };
    // A part that fails mid-run must not be reported as a clean send, and must
    // not hide the parts that DID land — the operator needs to know the message
    // they are reading is truncated.
    let sent;
    try {
      sent = await config.bot.sendMessage(org.telegram_chat_id, parts[i], partOpts);
    } catch (err) {
      throw new Error(
        `Part ${i + 1}/${parts.length} failed: ${err.message}. `
        + `Delivered so far: ${ids.length ? ids.join(', ') : 'none'} — the channel now `
        + 'holds a PARTIAL message; send the remainder or delete what landed.'
      );
    }
    if (!sent || !sent.message_id) {
      throw new Error(
        `Part ${i + 1}/${parts.length} returned no message_id — treat this as NOT delivered. `
        + `Delivered so far: ${ids.length ? ids.join(', ') : 'none'}`
      );
    }
    ids.push(sent.message_id);
  }

  const sent = { message_id: ids[0], date: Math.floor(Date.now() / 1000) };
  console.log(JSON.stringify({
    ok: true,
    org: org.name,
    chat_id: org.telegram_chat_id,
    message_id: sent.message_id,
    parts: ids.length,
    message_ids: ids,
    date: sent.date
  }));
}

// ---------------------------------------------------------------------------

const USAGE = `JEFF BOX — operator presence in a partner Telegram chat

  node scripts/jeffbox.js tail --org PD [--interval 30] [--since ISO] [--once]
  node scripts/jeffbox.js say  --org PD (--text "..." | --file PATH) [--reply MSG_ID]
                               [--topic general|inbox|alerts] [--raw] [--dry-run]

'tail' prints one line per inbound message — arm it with a persistent Monitor.
'say' prints the Telegram message_id, which is the only proof of delivery.
Every 'say' is prefixed with "JEFF BOX" unless --raw, so operators can tell a
human-driven session from Baba's automated replies on the same bot account.
`;

async function main() {
  const argv = process.argv.slice(2);
  const cmd = argv[0];
  const args = parseArgs(argv.slice(1));

  if (!cmd || args.help || cmd === 'help') {
    process.stdout.write(USAGE);
    return;
  }
  if (cmd === 'tail') return cmdTail(args);
  if (cmd === 'say') return cmdSay(args);
  throw new Error(`Unknown command "${cmd}"\n\n${USAGE}`);
}

// Guarded so the pure helpers below can be required by the test suite without
// the CLI running (and calling process.exit) on import.
if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((err) => {
      // Stdout, with the prefix the monitor's grep passes: a monitor command
      // routinely sends stderr to /dev/null, and an unreported fatal error
      // looks exactly like a channel that has gone quiet.
      console.log(`${WARN}: ${err.message}`);
      console.error(`[jeffbox] ${err.message}`);
      process.exit(1);
    });
}

module.exports = {
  parseArgs,
  parseInterval,
  parseSince,
  resolveTopicId,
  formatEvent,
  composeBody,
  splitForTelegram,
  resolveText,
  TG_LIMIT,
  assertRealBot,
  createSeen,
  buildRemoteProgram,
  PREFIX,
  WARN,
  REPO
};
