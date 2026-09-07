// ==============================================================================
// The boot and shutdown animation — one drawing per moment in time
// ==============================================================================
// PLAIN ENGLISH
//
// This file is the ANIMATION. Not a description of it, not a copy of it — this
// is where the shapes come from.
//
// Two stories, and this file draws both:
//
//   THE POUR (starting up).  AquariusOS is named after Aquarius, the
//     water-bearer. So the "A" is POURED. A thin stream falls from above the
//     screen into the point at the top of the A; both legs then run downward
//     from that point like water in two channels; the wave that crosses the A
//     spills out from left to right; and the word "AquariusOS" fades in
//     underneath. Two and a bit seconds, and then it stops and holds still
//     until the login screen takes over.
//
//   THE WIND (shutting down).  The opposite. The word fades out first, then the
//     wind takes the mark apart — the left leg wears away from its foot upward,
//     the right leg from the point downward, the wave last — and each stroke
//     breaks into drops that stream off to the right and fade. Just under two
//     seconds, and then the screen is dark.
//
// ------------------------------------------------------------------------------
// HOW A "FRAME" WORKS
// ------------------------------------------------------------------------------
// A moving picture is a stack of still pictures shown quickly one after
// another. Each still picture is a FRAME. Ours run at 30 frames per second, so
// the 2.2-second pour is 66 frames and the 1.9-second wind is 57.
//
// The two functions below — `bootFrame` and `shutFrame` — each take a moment in
// time, written as a number from 0 (the very start) to 1 (the very end), and
// hand back the drawing for that one moment. Ask for 66 moments spread evenly
// between 0 and 1 and you have the pour.
//
// Nothing here draws to the screen and nothing here writes a file. These are
// drawings in a text format called SVG. Turning them into the picture files the
// boot screen needs is `branding/render-plymouth-assets.sh`'s job, and that is
// the script you actually run.
//
// ------------------------------------------------------------------------------
// WHY THE WORD IS A SHAPE AND NOT TEXT
// ------------------------------------------------------------------------------
// "AquariusOS" is set in Sora. If it were left as text, whatever program draws
// these pictures would have to have Sora installed, and the day it does not the
// word silently comes out in some other typeface.
//
// So the letters are turned into an OUTLINE — a shape with no typeface attached
// — once, here, on the Mac, by the same helper the app icons use
// (`branding/icons/outline.mjs`). It reads the very Sora file the operating
// system itself ships. What ends up in the picture files is that shape, and
// nothing at boot time ever goes looking for a font.
//
// ------------------------------------------------------------------------------
// RUNNING IT BY HAND (you almost certainly do not want to)
// ------------------------------------------------------------------------------
//     node branding/pour.mjs --out <folder> [--size 288]
//
// writes one small HTML page per frame into <folder> — boot-0001.html …
// boot-0066.html, shutdown-0001.html … shutdown-0057.html, and hold.html. Each
// page holds one frame's drawing and nothing else, ready to be photographed by
// Chrome. `branding/render-plymouth-assets.sh` does that for you.
// ==============================================================================
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { outlineText } from './icons/outline.mjs';

// ------------------------------------------------------------------------------
// The colours — Midnight, from branding/tokens.md
// ------------------------------------------------------------------------------
// The boot screen is a dark screen, so it uses the Midnight half of the palette,
// the same one the desktop shows in dark mode. Never pick one of these by eye:
// copy it out of tokens.md.
export const M = {
  bg: '#0B1220',        // the ground the boot screen is painted on
  accent: '#00BFFF',    // aquariusBlue — the water
  indigo: '#9B82FF',    // the far end of the A's gradient
  gold: '#E6B947',      // the near end of the wave's gradient
  ink: '#DCE9F4',       // the word "AquariusOS"
};

// ------------------------------------------------------------------------------
// The shapes, and how long each part of the animation lasts
// ------------------------------------------------------------------------------
// These are the SAME numbers as branding/logo-midnight.svg — the mark as it is
// drawn everywhere else — with one difference: the A is written as two separate
// strokes that both START at the point on top, so that both legs can be drawn
// downward at the same time, like water running down two channels. Drawn as one
// continuous line it would have to fill from one foot, up, and down again.
const STROKE = 'stroke-width="5" stroke-linecap="round" stroke-linejoin="round" fill="none"';
const LEG_L = 'M32 12L14 54';     // the point, down to the left foot
const LEG_R = 'M32 12L50 54';     // the point, down to the right foot
const LEG_LENGTH = 45.7;          // how long one leg is: √(18² + 42²)
const WAVE = 'M20 40q6-6 12 0t12 0';
const WAVE_LENGTH = 27.2;

// How many frames each animation is, and how fast they are played back. 2.2
// seconds of pour and 1.9 seconds of wind, both at 30 pictures a second.
export const FPS = 30;
export const BOOT_FRAMES = 66;    // 2.2 s
export const WIND_FRAMES = 57;    // 1.9 s

// The frame size, in pixels, at one-times. See the long note about screen sizes
// in branding/render-plymouth-assets.sh.
export const FRAME_W = 288;
export const FRAME_H = 389;

// ------------------------------------------------------------------------------
// Two bits of arithmetic used all through the drawings
// ------------------------------------------------------------------------------
// `clamp` keeps a number between 0 and 1 — it is how "this part has not started
// yet" and "this part has finished" are written without an `if` on every line.
//
// `ease` bends a straight 0-to-1 into a slow-fast-slow one. Water does not start
// and stop instantly, and neither does anything else that should look alive.
const clamp = (v) => Math.max(0, Math.min(1, v));
const ease = (t) => (t < 0 ? 0 : t > 1 ? 1 : (t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2));

// ------------------------------------------------------------------------------
// The word, turned into a shape once
// ------------------------------------------------------------------------------
// Worked out the first time this file is loaded and then reused for every frame,
// because it is the same shape in all 123 of them.
//
// The numbers match what the drawing used while it was being designed: the word
// sits on a line 78 units down, centred on 32 (the middle of the 64-wide grid),
// 9.5 units tall, at Sora's Bold weight, with the letters pulled very slightly
// together (-0.2 units, written here as a fraction of the letter height because
// that is what the outline helper wants).
const WORDMARK = outlineText('AquariusOS', {
  em: 9.5,
  baseline: 78,
  cx: 32,
  wght: 700,
  tracking: -0.2 / 9.5,
});

// `word(opacity)` is the word as it appears in one frame — invisible at 0, fully
// there at 1.
const word = (opacity) =>
  `<path d="${WORDMARK.d}" fill="${M.ink}" opacity="${opacity.toFixed(2)}"/>`;

// ------------------------------------------------------------------------------
// The bits every frame shares: the gradients and the glow
// ------------------------------------------------------------------------------
// `id` has to be different in every frame. Two drawings on one page that both
// call their gradient "a" would end up sharing one gradient, and we do put many
// frames on one page while checking them.
const defs = (id, streamTop) => `<defs>
    <linearGradient id="a${id}" x1="14" y1="54" x2="50" y2="12" gradientUnits="userSpaceOnUse"><stop stop-color="${M.accent}"/><stop offset="1" stop-color="${M.indigo}"/></linearGradient>
    <linearGradient id="w${id}" x1="20" y1="40" x2="44" y2="40" gradientUnits="userSpaceOnUse"><stop stop-color="${M.gold}"/><stop offset="1" stop-color="${M.accent}"/></linearGradient>
    <linearGradient id="s${id}" x1="32" y1="${streamTop}" x2="32" y2="12" gradientUnits="userSpaceOnUse"><stop stop-color="${M.indigo}" stop-opacity="0"/><stop offset=".6" stop-color="${M.indigo}"/><stop offset="1" stop-color="${M.accent}"/></linearGradient>
    <filter id="g${id}" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="3"/></filter>
  </defs>`;

const open = (size) =>
  `<svg width="${size}" height="${Math.round(size * 1.35)}" viewBox="0 -16 64 102" xmlns="http://www.w3.org/2000/svg" style="overflow:visible">`;

// ==============================================================================
// THE POUR — one frame of it
// ==============================================================================
// `t` is the moment, 0 at the start and 1 at the end. What happens when:
//
//   0.00 – 0.15   the stream falls from above the screen into the point
//   0.15 – 0.60   both legs run downward from the point
//   0.45 – 0.65   the stream thins away, its job done
//   0.55 – 0.80   the wave spills out from left to right
//   0.70 – 1.00   the word fades in underneath
//
// Those overlap on purpose. A sequence where each part waits politely for the
// last one to finish reads as a list of events; one where they overlap reads as
// a single movement.
export function bootFrame(size = FRAME_W, t = 1, { showWord = true } = {}) {
  const id = 'b' + Math.round(t * 1000) + '-' + size;

  const stream = clamp(t / 0.15);           // how far down the stream has fallen
  const streamGone = clamp((t - 0.45) / 0.2); // and how far through thinning away it is
  const legs = ease(clamp((t - 0.15) / 0.45));
  const wave = ease(clamp((t - 0.55) / 0.25));
  const wordIn = clamp((t - 0.7) / 0.3);

  // The stream starts 14 units above the top of the mark and ends at the point.
  const streamTop = -14;
  const streamY = streamTop + (12 - streamTop) * stream;

  // A single drop, running just ahead of the stream, so the water reads as
  // falling rather than as a line growing.
  const drop = stream > 0.2 && streamGone < 1
    ? `<circle cx="32" cy="${(streamY - 6).toFixed(1)}" r="1.6" fill="${M.accent}"/>`
    : '';

  return `${open(size)}
  ${defs(id, streamTop)}
  <g filter="url(#g${id})" opacity="${(0.3 * legs).toFixed(2)}"><path d="${LEG_L}" stroke="${M.accent}" ${STROKE}/><path d="${LEG_R}" stroke="${M.accent}" ${STROKE}/><path d="${WAVE}" stroke="${M.gold}" ${STROKE} opacity="${wave}"/></g>
  <path d="M32 ${streamTop}L32 ${streamY.toFixed(1)}" stroke="url(#s${id})" stroke-width="${(3.2 * (1 - streamGone) + 0.01).toFixed(2)}" stroke-linecap="round" fill="none" opacity="${(1 - streamGone).toFixed(2)}"/>
  ${drop}
  <path d="${LEG_L}" stroke="url(#a${id})" ${STROKE} stroke-dasharray="${LEG_LENGTH} ${LEG_LENGTH * 2}" stroke-dashoffset="${(LEG_LENGTH * (1 - legs)).toFixed(2)}"/>
  <path d="${LEG_R}" stroke="url(#a${id})" ${STROKE} stroke-dasharray="${LEG_LENGTH} ${LEG_LENGTH * 2}" stroke-dashoffset="${(LEG_LENGTH * (1 - legs)).toFixed(2)}"/>
  ${legs > 0.02 ? `<circle cx="32" cy="12" r="2.5" fill="${M.indigo}"/>` : ''}
  <path d="${WAVE}" stroke="url(#w${id})" ${STROKE} stroke-dasharray="${WAVE_LENGTH} ${WAVE_LENGTH * 2}" stroke-dashoffset="${(WAVE_LENGTH * (1 - wave)).toFixed(2)}"/>
  ${showWord ? word(wordIn) : ''}
</svg>`;
}

// ==============================================================================
// THE WIND — one frame of it
// ==============================================================================
// The wind comes from the left. What happens when:
//
//   0.00 – 0.25   the word fades out
//   0.10 – 0.60   the left leg wears away, from its foot up toward the point
//   0.25 – 0.75   the right leg wears away, from the point down to its foot
//   0.45 – 0.90   the wave goes last
//
// and as each part of a stroke disappears, a drop is released from that exact
// spot, streams off to the right, drifts a little, and fades. The drops are what
// make it read as "blown away" rather than "erased".
export function shutFrame(size = FRAME_W, t = 0, { showWord = true } = {}) {
  const id = 's' + Math.round(t * 1000) + '-' + size;

  const wordOut = 1 - clamp(t / 0.25);
  const erodeL = ease(clamp((t - 0.1) / 0.5));
  const erodeR = ease(clamp((t - 0.25) / 0.5));
  const erodeW = ease(clamp((t - 0.45) / 0.45));

  // How far right a drop has travelled, given how long ago it was released.
  const drift = (age) => age * 38;
  // A point on one leg. `k` is 0 at the point on top and 1 at the foot.
  const legPoint = (k, left) => ({ x: 32 + (left ? -1 : 1) * 18 * k, y: 12 + 42 * k });

  const drops = [];
  const release = (count, at, over, place, gold) => {
    for (let i = 0; i < count; i++) {
      const k = i / (count - 1);
      const age = clamp((t - at(k)) / over);
      if (age > 0 && age < 1) drops.push({ ...place(k, i, age), a: 1 - age, gold });
    }
  };
  // The left leg's drops: released foot-first, as the wind reaches them.
  release(7, (k) => k * 0.5 + 0.1, 0.5, (k, i, age) => {
    const p = legPoint(1 - k, true);
    return { x: p.x + drift(age), y: p.y - 6 * age + (i % 2 ? 2 : -2) * age, r: 1.4 - 0.6 * age };
  }, false);
  // The right leg's, a third of a second later.
  release(7, (k) => k * 0.5 + 0.25, 0.5, (k, i, age) => {
    const p = legPoint(1 - k, false);
    return { x: p.x + drift(age), y: p.y - 6 * age + (i % 2 ? -2 : 2) * age, r: 1.4 - 0.6 * age };
  }, false);
  // And the wave's, last of all, in the wave's own gold.
  release(6, (k) => k * 0.45 + 0.45, 0.45, (k, i, age) => ({
    x: 20 + 24 * k + drift(age), y: 40 - 4 * age, r: 1.3 - 0.5 * age,
  }), true);

  return `${open(size)}
  ${defs(id, -14)}
  <g filter="url(#g${id})" opacity="${(0.3 * (1 - erodeW)).toFixed(2)}"><path d="${LEG_L}" stroke="${M.accent}" ${STROKE}/><path d="${LEG_R}" stroke="${M.accent}" ${STROKE}/></g>
  <path d="M14 54L32 12" stroke="url(#a${id})" ${STROKE} stroke-dasharray="${LEG_LENGTH} ${LEG_LENGTH * 2}" stroke-dashoffset="${(-LEG_LENGTH * erodeL).toFixed(2)}"/>
  <path d="${LEG_R}" stroke="url(#a${id})" ${STROKE} stroke-dasharray="${LEG_LENGTH} ${LEG_LENGTH * 2}" stroke-dashoffset="${(-LEG_LENGTH * erodeR).toFixed(2)}"/>
  <path d="${WAVE}" stroke="url(#w${id})" ${STROKE} stroke-dasharray="${WAVE_LENGTH} ${WAVE_LENGTH * 2}" stroke-dashoffset="${(-WAVE_LENGTH * erodeW).toFixed(2)}"/>
  ${drops.map((p) => `<circle cx="${p.x.toFixed(1)}" cy="${p.y.toFixed(1)}" r="${p.r.toFixed(2)}" fill="${p.gold ? M.gold : M.accent}" opacity="${p.a.toFixed(2)}"/>`).join('')}
  ${showWord ? word(wordOut) : ''}
</svg>`;
}

// ==============================================================================
// Writing one page per frame, ready to be photographed
// ==============================================================================
// Each page holds one frame and nothing else. The background is left
// TRANSPARENT on purpose: the boot screen paints its own Midnight ground behind
// these pictures, so a background baked into them would show up as a rectangle
// around the mark.
const page = (svg) => `<!doctype html><meta charset="utf-8">
<style>html,body{margin:0;padding:0;overflow:hidden;background:transparent}</style>
${svg}
`;

// A frame's file name. FOUR DIGITS, always — boot-0001, not boot-1. The boot
// screen's own script builds these names the same way, and one that does not
// match is a picture that never appears.
export const frameName = (prefix, n) => `${prefix}-${String(n).padStart(4, '0')}`;

function main() {
  const args = process.argv.slice(2);
  const opt = (flag, fallback) => {
    const i = args.indexOf(flag);
    return i === -1 ? fallback : args[i + 1];
  };
  const out = opt('--out', null);
  const size = Number(opt('--size', FRAME_W));

  if (!out) {
    console.error('pour.mjs: --out <folder> is required. Run branding/render-plymouth-assets.sh instead.');
    process.exit(1);
  }
  if (!Number.isInteger(size) || size < 32 || size > 2048) {
    console.error(`pour.mjs: --size ${opt('--size')} is not a whole number of pixels between 32 and 2048.`);
    process.exit(1);
  }

  mkdirSync(out, { recursive: true });
  let written = 0;

  // The pour. Frame 1 is the very start (t = 0) and frame 66 is the very end
  // (t = 1), with the other 64 spread evenly between them.
  for (let n = 1; n <= BOOT_FRAMES; n++) {
    const t = (n - 1) / (BOOT_FRAMES - 1);
    writeFileSync(join(out, `${frameName('boot', n)}.html`), page(bootFrame(size, t)));
    written++;
  }

  // The wind.
  for (let n = 1; n <= WIND_FRAMES; n++) {
    const t = (n - 1) / (WIND_FRAMES - 1);
    writeFileSync(join(out, `${frameName('shutdown', n)}.html`), page(shutFrame(size, t)));
    written++;
  }

  // The hold: the finished mark, standing still. It is the pour's LAST frame,
  // asked for in exactly the same words, so the moment the pour stops there is
  // no jump. The render script proves the two pictures are byte-for-byte the
  // same after they are drawn.
  writeFileSync(join(out, 'hold.html'), page(bootFrame(size, 1)));
  written++;

  console.log(`pour.mjs: wrote ${written} frame pages at ${size}px into ${out}`);
}

// Only run the writing part when this file is started directly, so that
// importing it (to reuse `bootFrame`) does not write anything.
if (process.argv[1] && process.argv[1].endsWith('pour.mjs')) main();
