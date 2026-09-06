// ==============================================================================
// Turn short text into an outline — used for the "DR" in the two Resolve icons
// ==============================================================================
// An icon must not depend on a font being installed on the machine that draws
// it. So the two letters are turned into a SHAPE here, once, on the Mac, and
// what ships is that shape. Nothing at run time ever looks for Sora.
//
// The font it reads is THE ONE THE OPERATING SYSTEM ALREADY SHIPS, two folders
// up in system_files/. That is deliberate: a second copy of a font file in this
// repo is a second thing to keep up to date, and the day they drift the icons
// stop matching the interface they sit in.
//
// Usage: outlineText('DR', { em, baseline, cx, wght })
// ==============================================================================
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
const require = createRequire(import.meta.url);
const fontkit = require('fontkit');

// ⚠️ The font's file name has SQUARE BRACKETS in it — Sora[wght].ttf — and that
// is why this is built with path.join instead of `new URL(...).pathname`. A URL
// escapes those two characters to %5B and %5D, and fontkit is then handed a
// path with no such file at it.
const FONT = join(dirname(fileURLToPath(import.meta.url)),
                  '..', '..', 'system_files', 'usr', 'share', 'fonts', 'sora-fonts', 'Sora[wght].ttf');
const base = fontkit.openSync(FONT);

export function outlineText(text, { em=27, baseline=38, cx=32, wght=700, tracking=-0.02 }={}){
  const font = base.getVariation({ wght });
  const k = em / font.unitsPerEm;
  const run = font.layout(text);
  const advances = run.positions.map(p=>p.xAdvance*k + tracking*em);
  const width = advances.reduce((a,b)=>a+b,0) - tracking*em; // no tracking after the last letter
  let x = cx - width/2; const parts=[];
  run.glyphs.forEach((g,i)=>{
    const ox=x, oy=baseline;
    for (const c of g.path.commands){
      const X=(v)=>+(ox+v*k).toFixed(2), Y=(v)=>+(oy-v*k).toFixed(2);
      if (c.command==='moveTo') parts.push(`M${X(c.args[0])} ${Y(c.args[1])}`);
      else if (c.command==='lineTo') parts.push(`L${X(c.args[0])} ${Y(c.args[1])}`);
      else if (c.command==='quadraticCurveTo') parts.push(`Q${X(c.args[0])} ${Y(c.args[1])} ${X(c.args[2])} ${Y(c.args[3])}`);
      else if (c.command==='bezierCurveTo') parts.push(`C${X(c.args[0])} ${Y(c.args[1])} ${X(c.args[2])} ${Y(c.args[3])} ${X(c.args[4])} ${Y(c.args[5])}`);
      else if (c.command==='closePath') parts.push('Z');
    }
    x += advances[i];
  });
  return { d: parts.join(''), width, capHeight: font.capHeight*k };
}
