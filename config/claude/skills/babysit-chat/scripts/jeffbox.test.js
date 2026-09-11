'use strict';
/**
 * Tests for the pure helpers behind `scripts/jeffbox.js`.
 *
 * The properties pinned here are the ones whose failure is SILENT: a message
 * that goes out unmarked reads as a bot message; a topic that falls back to
 * General reports a real message_id for a message nobody asked to put there;
 * an interval that parses to NaN becomes an unbounded ssh loop; and — the one
 * that matters most — a stub bot resolves a fabricated `message_id`, forging
 * the single value this tool treats as proof of delivery. None of these throw
 * on their own; they quietly do the wrong thing and report success.
 */

const { expect } = require('chai');

const {
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
  REPO
} = require('./jeffbox');

describe('jeffbox', () => {
  describe('assertRealBot', () => {
    // telegram-config exports `isNoopBot` as a BOOLEAN (`!token`) and always
    // assigns a truthy `bot`. A guard written as `typeof isNoopBot ===
    // 'function' ? isNoopBot() : false` is therefore dead code, and the stub's
    // `sendMessage` resolves `{message_id: 1}` — success, with proof, having
    // sent nothing.
    it('rejects the no-op stub bot', () => {
      expect(() => assertRealBot({ bot: { sendMessage: () => {} }, isNoopBot: true }))
        .to.throw(/no-op stub/);
    });

    it('accepts a real bot', () => {
      expect(() => assertRealBot({ bot: { sendMessage: () => {} }, isNoopBot: false }))
        .to.not.throw();
    });

    it('rejects a missing bot', () => {
      expect(() => assertRealBot({ bot: null, isNoopBot: false })).to.throw(/no-op stub/);
      expect(() => assertRealBot(undefined)).to.throw(/no-op stub/);
    });

    it('matches the real telegram-config export shape', () => {
      // Guards the assumption the whole check rests on: if isNoopBot ever
      // becomes a function, `config.isNoopBot` is truthy for a REAL bot and
      // every send starts failing loudly — which is the safe direction, but
      // this test says why.
      const config = require(require('path').join(REPO, 'src/config/telegram-config'));
      expect(config).to.have.property('isNoopBot');
      expect(typeof config.isNoopBot).to.equal('boolean');
      expect(config.bot).to.be.an('object');
    });
  });

  describe('composeBody', () => {
    it('prefixes every message with JEFF BOX', () => {
      expect(composeBody('the backfill is done', false)).to.equal(`${PREFIX}\n\nthe backfill is done`);
    });

    it('separates the marker from the body with a blank line', () => {
      // Telegram collapses a single newline into the same visual paragraph, so
      // the marker would read as part of the first sentence.
      expect(composeBody('hello', false).startsWith(`${PREFIX}\n\n`)).to.equal(true);
    });

    it('omits the marker only when raw is explicitly set', () => {
      expect(composeBody('hello', true)).to.equal('hello');
    });

    it('does not treat a falsy-but-present raw flag as raw', () => {
      expect(composeBody('hello', undefined)).to.equal(`${PREFIX}\n\nhello`);
    });
  });

  describe('resolveTopicId', () => {
    const org = { name: 'PD', telegram_topics: { inbox: '3', alerts: '6', general: null } };

    it('resolves a named topic to a number', () => {
      expect(resolveTopicId(org, 'inbox')).to.equal(3);
      expect(resolveTopicId(org, 'alerts')).to.equal(6);
    });

    it('returns null for general so the message lands unthreaded', () => {
      // The operators talk in the group's General area; a message_thread_id
      // would bury the reply in a forum topic nobody is reading.
      expect(resolveTopicId(org, 'general')).to.equal(null);
    });

    it('throws rather than silently posting an unknown topic to General', () => {
      // The dangerous direction: a fallback delivers to the wrong place AND
      // returns a real message_id, so the operator has proof of the wrong send.
      expect(() => resolveTopicId(org, 'feedback')).to.throw(/no "feedback" topic/);
      expect(() => resolveTopicId(org, 'inbxo')).to.throw(/known topics/);
    });

    it('throws when --topic was given with no value', () => {
      expect(() => resolveTopicId(org, true)).to.throw(/needs a value/);
    });

    it('parses telegram_topics when MySQL hands it back as a JSON string', () => {
      const stringy = { name: 'PD', telegram_topics: '{"inbox":"3","alerts":"6"}' };
      expect(resolveTopicId(stringy, 'inbox')).to.equal(3);
    });

    it('throws on unparseable telegram_topics rather than posting to General', () => {
      expect(() => resolveTopicId({ name: 'PD', telegram_topics: '{not json' }, 'inbox'))
        .to.throw(/no "inbox" topic/);
    });
  });

  describe('parseInterval', () => {
    it('defaults to 30s', () => {
      expect(parseInterval(undefined)).to.equal(30000);
      expect(parseInterval(true)).to.equal(30000);
    });

    it('accepts a positive number of seconds', () => {
      expect(parseInterval('45')).to.equal(45000);
    });

    it('rejects a unit suffix instead of looping every millisecond', () => {
      // Number('30s') is NaN and setTimeout(fn, NaN) fires in ~1ms — a typo
      // becomes an unbounded stream of ssh processes, silently.
      expect(() => parseInterval('30s')).to.throw(/positive number/);
    });

    it('rejects zero and negatives', () => {
      expect(() => parseInterval('0')).to.throw(/positive number/);
      expect(() => parseInterval('-5')).to.throw(/positive number/);
    });
  });

  describe('parseSince', () => {
    it('defaults to now, so a monitor reports from when it was armed', () => {
      const before = Date.now();
      const got = new Date(parseSince(undefined)).getTime();
      expect(got).to.be.at.least(before);
    });

    it('accepts an explicit UTC instant', () => {
      expect(parseSince('2026-08-25T09:00:00Z')).to.equal('2026-08-25T09:00:00.000Z');
    });

    it('accepts an explicit offset', () => {
      expect(parseSince('2026-08-25T09:00:00+02:00')).to.equal('2026-08-25T07:00:00.000Z');
    });

    it('rejects a timezone-less value instead of shifting the window', () => {
      // new Date('2026-08-25 09:00') is LOCAL time; west of UTC that silently
      // skips hours of the backlog the command exists to read.
      expect(() => parseSince('2026-08-25 09:00')).to.throw(/explicit timezone/);
      expect(() => parseSince('2026-08-25')).to.throw(/explicit timezone/);
    });

    it('names the flag when the value is unparseable', () => {
      expect(() => parseSince('not-a-dateZ')).to.throw(/--since/);
    });
  });

  describe('formatEvent', () => {
    const row = {
      created_at: '2026-08-25T15:12:52.545Z',
      sender_name: 'Kyle',
      topic_id: 0,
      telegram_message_id: 1708,
      message_text: 'this is not showing the new link'
    };

    it('renders time, sender, message id and text', () => {
      expect(formatEvent(row)).to.equal('[15:12:52Z] Kyle #1708: this is not showing the new link');
    });

    it('collapses newlines so one message stays one Monitor event', () => {
      const multi = { ...row, message_text: 'line one\nline two\n\nline three' };
      const out = formatEvent(multi);
      expect(out).to.not.include('\n');
      expect(out).to.include('line one / line two / line three');
    });

    it('shows a topic id only when the message is in a forum topic', () => {
      expect(formatEvent(row)).to.not.include('t0');
      expect(formatEvent({ ...row, topic_id: 133 })).to.include('t133');
    });

    it('renders a message with no text rather than printing undefined', () => {
      expect(formatEvent({ ...row, message_text: null })).to.equal('[15:12:52Z] Kyle #1708: ');
    });
  });

  describe('buildRemoteProgram', () => {
    it('queries inclusively so two messages sharing a timestamp both arrive', () => {
      // With `>` the second message at an identical created_at is skipped
      // forever once the first advances the cursor. Dedupe is createSeen's job.
      expect(buildRemoteProgram(6, '2026-08-25T15:00:00.000Z')).to.include('created_at >= ?');
    });

    it('embeds the org and cursor as JSON literals, never as raw text', () => {
      const prog = buildRemoteProgram(6, '2026-08-25T15:00:00.000Z');
      expect(prog).to.include('"6"');
      expect(prog).to.include('"2026-08-25T15:00:00.000Z"');
    });
  });

  describe('createSeen', () => {
    it('suppresses a row already emitted', () => {
      const seen = createSeen();
      seen.add(1);
      expect(seen.has(1)).to.equal(true);
      expect(seen.has(2)).to.equal(false);
    });

    it('stays bounded over a session-length run', () => {
      const seen = createSeen(10);
      for (let i = 0; i < 100; i += 1) seen.add(i);
      expect(seen.size).to.equal(10);
      expect(seen.has(99)).to.equal(true);
      expect(seen.has(0)).to.equal(false);
    });

    it('ignores a repeated add rather than double-counting it', () => {
      const seen = createSeen(10);
      seen.add(7);
      seen.add(7);
      expect(seen.size).to.equal(1);
    });
  });

  describe('parseArgs', () => {
    it('reads flag values and bare flags', () => {
      const a = parseArgs(['--org', 'PD', '--text', 'hi', '--dry-run']);
      expect(a.org).to.equal('PD');
      expect(a.text).to.equal('hi');
      expect(a['dry-run']).to.equal(true);
    });

    it('treats a following flag as the end of a valueless flag', () => {
      const a = parseArgs(['--once', '--org', 'PD']);
      expect(a.once).to.equal(true);
      expect(a.org).to.equal('PD');
    });

    it('passes a dash-leading message through after --', () => {
      // Without the terminator `--text "--- status ---"` parses the message as
      // a flag name and the send is rejected as if no text were given.
      const a = parseArgs(['--org', 'PD', '--', '--- status ---']);
      expect(a._[0]).to.equal('--- status ---');
      expect(a.org).to.equal('PD');
    });
  });

  // Telegram rejects a sendMessage body over 4096 UTF-16 units. Before this the
  // over-length case was simply unhandled: the API refused the whole send, and
  // since a failed send is the one outcome this tool exists to make visible, a
  // long message turned into an error exactly when an operator was waiting.
  describe('splitForTelegram', () => {
    const para = (n, ch = 'x') => ch.repeat(n);

    it('leaves a message that fits completely alone — no marker, no copy', () => {
      const body = 'JEFF BOX\n\nshort enough';
      expect(splitForTelegram(body)).to.deep.equal([body]);
    });

    it('leaves a message at exactly the limit alone', () => {
      // Off-by-one here splits a message that did not need splitting, which
      // appends a "(1/2)" marker to something that reads fine unmarked.
      const body = para(TG_LIMIT);
      expect(splitForTelegram(body)).to.have.length(1);
    });

    it('keeps every part within the limit', () => {
      const parts = splitForTelegram(para(TG_LIMIT * 3));
      expect(parts.length).to.be.greaterThan(1);
      for (const p of parts) expect(p.length).to.be.at.most(TG_LIMIT);
    });

    it('loses no content across the split', () => {
      // The failure this guards is the quiet one: a splitter that drops a
      // paragraph still returns plausible-looking parts, and nobody notices
      // until the missing sentence mattered.
      const body = ['alpha', para(3000), 'beta', para(3000), 'gamma'].join('\n\n');
      const rejoined = splitForTelegram(body)
        .map(p => p.replace(/\n\n\(\d+\/\d+\)$/, ''))
        .join('\n\n');
      expect(rejoined.replace(/\s+/g, ' ')).to.equal(body.replace(/\s+/g, ' '));
    });

    it('prefers a paragraph boundary over a mid-word cut', () => {
      const body = `${para(3000)}\n\n${para(3000)}`;
      const [first] = splitForTelegram(body);
      // The marker is part of what is sent, so strip it before comparing the
      // content — asserting on the marked string would pass for a cut in the
      // wrong place as long as the marker were right.
      expect(first.replace(/\n\n\(\d+\/\d+\)$/, '')).to.equal(para(3000));
    });

    it('marks each part so a reader can tell the message is not complete', () => {
      // TG_LIMIT + 500 is deliberately just over one part's worth: each part
      // carries only `TG_LIMIT - MARKER_ROOM`, so TG_LIMIT * 2 would be THREE
      // parts, not two.
      const parts = splitForTelegram(para(TG_LIMIT + 500));
      expect(parts).to.have.length(2);
      expect(parts[0]).to.match(/\(1\/2\)$/);
      expect(parts[1]).to.match(/\(2\/2\)$/);
    });

    it('numbers every part of a three-part message correctly', () => {
      const parts = splitForTelegram(para(TG_LIMIT * 2));
      expect(parts).to.have.length(3);
      expect(parts.map((p, i) => new RegExp(`\\(${i + 1}/3\\)$`).test(p)))
        .to.deep.equal([true, true, true]);
    });

    it('still splits a single unbroken line with no boundary to find', () => {
      // No paragraph, no newline, no space. A hard cut is wrong-looking but a
      // refusal to send at all is worse.
      const parts = splitForTelegram(para(TG_LIMIT + 500));
      expect(parts).to.have.length(2);
      for (const p of parts) expect(p.length).to.be.at.most(TG_LIMIT);
    });
  });

  describe('resolveText', () => {
    const fs = require('fs');
    const os = require('os');
    const path = require('path');
    let tmp;

    beforeEach(() => {
      tmp = path.join(os.tmpdir(), `jeffbox-test-${process.pid}-${Math.random()}.txt`);
    });
    afterEach(() => { try { fs.unlinkSync(tmp); } catch { /* never created */ } });

    it('reads --file so a long message need not ride on the command line', () => {
      fs.writeFileSync(tmp, 'from a file\n');
      expect(resolveText({ file: tmp, _: [] })).to.equal('from a file');
    });

    it('keeps interior blank lines, which are paragraph breaks', () => {
      fs.writeFileSync(tmp, 'one\n\ntwo\n\n\n');
      expect(resolveText({ file: tmp, _: [] })).to.equal('one\n\ntwo');
    });

    it('lets --text win over --file rather than merging them', () => {
      // A stale message file left in a scratch directory must never be able to
      // change what an explicit --text sends.
      fs.writeFileSync(tmp, 'stale');
      expect(resolveText({ text: 'explicit', file: tmp, _: [] })).to.equal('explicit');
    });

    it('refuses an empty file instead of sending a blank message', () => {
      fs.writeFileSync(tmp, '   \n\n');
      expect(() => resolveText({ file: tmp, _: [] })).to.throw(/empty/);
    });

    it('still honours --text and a positional argument', () => {
      expect(resolveText({ text: 'inline', _: [] })).to.equal('inline');
      expect(resolveText({ _: ['positional'] })).to.equal('positional');
    });
  });
});
