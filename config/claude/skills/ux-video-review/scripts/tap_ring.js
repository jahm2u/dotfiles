// tap_ring.js -- show where a tap lands, inside the page, so it is in the screencast.
// The DevTools screencast draws no pointer, so a reviewer cannot tell what was pressed.
// ux-evidence runs this with evaluate_script on the element it is about to click
// (args: [uid]), then clicks. The ring (44 px, white at 55%, grey border, shadow) snaps in
// with an overshoot (0.3 -> 1.15 -> 1, 0.18 s) and HOLDS, perfectly still, until the real tap
// lands (pointerdown/mousedown/touchstart/click). Then it pops: the core presses in and
// bursts out while two ripples race outward to 2.6x (~0.45 s). Holding matters: the agent's
// click lands seconds after this call, and a ring that played on its own was gone before
// the screen reacted (2026-10-19 test). Still while held, so the compose step can cut the
// wait; no idle pulse. Gone after 15 s if no tap comes.
// Returns Date.now(): with the value from right after screencast_start, that gives the
// step's exact time in the recording, so steps.txt need not be guessed from scene changes.
async (el) => {
  const r = el.getBoundingClientRect();
  const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
  const disc = (extra) => {
    const d = document.createElement('div');
    d.setAttribute('data-ux-tap-ring', '');
    Object.assign(d.style, {
      position: 'fixed', left: `${cx - 22}px`, top: `${cy - 22}px`, width: '44px', height: '44px',
      borderRadius: '50%', boxSizing: 'border-box', pointerEvents: 'none', zIndex: '2147483647',
    }, extra);
    document.documentElement.appendChild(d);
    return d;
  };
  const ring = disc({
    background: 'rgba(255,255,255,0.55)', border: '2px solid rgba(72,72,80,0.85)',
    boxShadow: '0 2px 12px rgba(0,0,0,0.35), 0 0 0 1px rgba(255,255,255,0.6)',
  });
  ring.animate([
    { transform: 'scale(0.3)', opacity: 0 },
    { transform: 'scale(1.15)', opacity: 1, offset: 0.65 },
    { transform: 'scale(1)', opacity: 1 },
  ], { duration: 180, easing: 'ease-out', fill: 'forwards' });
  let gone = false;
  const release = () => {
    if (gone) return;
    gone = true;
    ring.animate([
      { transform: 'scale(1)', opacity: 1 },
      { transform: 'scale(0.72)', opacity: 1, offset: 0.2 },
      { transform: 'scale(1.35)', opacity: 0 },
    ], { duration: 320, easing: 'ease-out', fill: 'forwards' }).finished.then(() => ring.remove());
    for (const [delay, width] of [[0, 3], [90, 2]]) {
      const wave = disc({
        border: `${width}px solid rgba(40,40,48,0.8)`,
        boxShadow: '0 0 0 2px rgba(255,255,255,0.85), inset 0 0 0 1px rgba(255,255,255,0.85)', opacity: '0',
      });
      wave.animate([
        { transform: 'scale(0.9)', opacity: 0.95 },
        { transform: 'scale(2.6)', opacity: 0 },
      ], { duration: 450, delay, easing: 'cubic-bezier(.15,.7,.3,1)', fill: 'forwards' })
        .finished.then(() => wave.remove());
    }
  };
  // Any of these means the tap landed. The DevTools MCP click did not fire pointerdown under
  // touch emulation (2026-10-19), so each ring held for its 15 s timeout.
  for (const type of ['pointerdown', 'mousedown', 'touchstart', 'click']) {
    window.addEventListener(type, release, { capture: true, once: true });
  }
  setTimeout(release, 15000);
  await new Promise((done) => setTimeout(done, 300));
  return Date.now();
}
