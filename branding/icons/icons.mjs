// AquariusOS app icons — one source for every icon, both themes. Geometry never changes between themes; only the palette.
import { outlineText } from './outline.mjs';

// ---------- tokens (os-image/branding/tokens.md) ----------
export const T = {
  void:'#06070C', s1:'#10121C', s2:'#161A29', s3:'#1D2236',
  starlight:'#8AB4FF', nebula:'#5B4BE0', ancient:'#E6DDB8', onAccent:'#080B14',
  text1:'#FFFFFF', text2:'#B4BACD', text3:'#848CA6',
  ring:'rgba(237,239,247,.14)', ringL:'rgba(20,23,38,.16)',
  L:{ bg:'#EEF0F7', s1:'#F7F8FC', s2:'#FFFFFF', starlight:'#3D63D6', nebula:'#4A3BC9', ancient:'#8A7B3D', text1:'#141726', text2:'#565C72', text3:'#8A90A6' },
  dockIce:'#E3ECF5', dockMidnight:'#111A2B',
};

// ---------- the two palettes (Royce, 2026-09-06: one slate plate for all; an Ice twin for the light theme) ----------
export const PALETTES = {
  midnight: { plate:[T.s3, T.s2], ring:T.ring, line:[T.starlight, T.nebula], gold:T.ancient, tool:T.text1, grey:T.text2, shadow:T.onAccent, shadowAlpha:.38 },
  ice:      { plate:[T.L.s2, T.L.s1], ring:T.ringL, line:[T.L.starlight, T.L.nebula], gold:T.L.ancient, tool:T.L.text1, grey:T.L.text2, shadow:T.L.text1, shadowAlpha:.22 },
};
const pal=(theme)=>PALETTES[theme]||PALETTES.midnight;

// THE WAVE — one shape, the logo's own (Royce's rule, 2026-09-06). `M20 40 q6-6 12 0 t12 0`: two humps, rise = half the hump.
export function wavePath(x, y, hump){ const r=hump/2; return `M${x} ${y}q${r}-${r} ${hump} 0t${hump} 0`; }
export const LOGO_WAVE = wavePath(20, 40, 12);
export const ICON_WAVE_Y = (y)=>wavePath(14, y, 18);   // the logo's wave at 1.5x, 36 wide, centred on 32

// THE MARK — the logo's "A" and wave, scaled uniformly about a centre. Stroke stays 5; only the geometry scales.
export function markPaths(cx, cy, k){
  const X=(x)=>+(cx+(x-32)*k).toFixed(2), Y=(y)=>+(cy+(y-33)*k).toFixed(2), R=(v)=>+(v*k).toFixed(2);
  return { A:`M${X(14)} ${Y(54)}L${X(30)} ${Y(12)}q${R(1.4)}-${R(3.6)} ${R(4)} 0L${X(50)} ${Y(54)}`, wave:wavePath(X(20), Y(40), R(12)) };
}

// THE GLYPH SHADOW — under the glyph, never under the plate. Dropped 1.5, blurred 1.6. A lift at 128+, gone by 32.
export function glyphShadow(id, P){ return `<filter id="sh${id}" x="-20%" y="-20%" width="140%" height="150%"><feGaussianBlur in="SourceAlpha" stdDeviation="1.6"/><feOffset dy="1.5" result="o"/><feFlood flood-color="${P.shadow}" flood-opacity="${P.shadowAlpha}"/><feComposite in2="o" operator="in" result="s"/><feMerge><feMergeNode in="s"/><feMergeNode in="SourceGraphic"/></feMerge></filter>`; }

export const S = 'stroke-width="5" stroke-linecap="round" stroke-linejoin="round" fill="none"';
const vgrad=(id,a,b)=>`<linearGradient id="${id}" x1="0" y1="0" x2="0" y2="64" gradientUnits="userSpaceOnUse"><stop stop-color="${a}"/><stop offset="1" stop-color="${b}"/></linearGradient>`;
const hgrad=(id,a,b,x1=16,x2=48)=>`<linearGradient id="${id}" x1="${x1}" y1="32" x2="${x2}" y2="32" gradientUnits="userSpaceOnUse"><stop stop-color="${a}"/><stop offset="1" stop-color="${b}"/></linearGradient>`;
export const svg=(size,defs,body)=>`<svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg"><defs>${defs}</defs>${body}</svg>`;

// one frame for every icon: the plate (radius 25%, hairline ring), the working-line gradient, the shadow, the lifted glyph
function icon(size, key, theme, shadow, build){
  const P=pal(theme); const id=key+theme[0]+(shadow?'s':'');
  const defs = vgrad('p'+id, P.plate[0], P.plate[1]) + hgrad('g'+id, P.line[0], P.line[1], 14, 50) + (shadow?glyphShadow(id,P):'');
  const line=`url(#g${id})`, plateFill=`url(#p${id})`;
  const extra={defs:''}; const glyph = build({P, line, plateFill, id, extra});
  const plate = `<rect width="64" height="64" rx="16" fill="${plateFill}"/><rect x="0.5" y="0.5" width="63" height="63" rx="15.5" fill="none" stroke="${P.ring}" stroke-width="1"/>`;
  return svg(size, defs+extra.defs, plate + (shadow?`<g filter="url(#sh${id})">${glyph}</g>`:glyph));
}

// EDITOR — the wave as a waveform, one gold playhead. ('track' = the cut-track alternate, not chosen)
export function editor(size, variant='simple', shadow=true, theme='midnight'){
  return icon(size,'ed'+variant,theme,shadow,({P,line})=> variant==='simple'
    ? `<path d="${ICON_WAVE_Y(32)}" stroke="${line}" ${S}/><path d="M32 15v34" stroke="${P.gold}" ${S}/>`
    : `<path d="M18 29q7-7 14 0t14 0" stroke="${line}" ${S}/><path d="M18 44h8M38 44h8" stroke="${line}" ${S}/><path d="M32 16v32" stroke="${P.gold}" ${S}/>`);
}
// WRITER — a pen (tool colour) with a gold nib, over the wave.
export function writer(size, shadow=true, theme='midnight'){
  return icon(size,'wr',theme,shadow,({P,line})=>
    `<path d="${ICON_WAVE_Y(47)}" stroke="${line}" ${S}/><path d="M46 11L33.8 30.1" stroke="${P.tool}" stroke-width="5" stroke-linecap="round" fill="none"/><path d="M35.9 31.5L31.7 28.8L30 36Z" fill="${P.gold}"/>`);
}
// FILES — a folder, nothing else. ('lid' / 'inside' = the wave candidates, not chosen)
export function files(size, variant='outline', shadow=true, theme='midnight'){
  const folder = `M13 20h12l4 4h22v23a3 3 0 0 1-3 3H16a3 3 0 0 1-3-3z`;
  return icon(size,'fi'+variant,theme,shadow,({line})=>
    variant==='lid' ? `<path d="${wavePath(13,26,19)}v18a3 3 0 0 1-3 3H16a3 3 0 0 1-3-3z" stroke="${line}" ${S}/>`
    : variant==='inside' ? `<path d="${folder}" stroke="${line}" ${S}/><path d="${wavePath(20,39,12)}" stroke="${line}" ${S}/>`
    : `<path d="${folder}" stroke="${line}" ${S}/>`);
}
// SETTINGS — two sliders in the Aquarius line, knobs in the tool colour (Royce, 2026-09-06). ('three' / 'dial' / 'cog' not chosen)
export function settings(size, variant='two', shadow=true, theme='midnight'){
  return icon(size,'se'+variant,theme,shadow,({P,line,plateFill})=>{
    const knob=(x,y)=>`<circle cx="${x}" cy="${y}" r="5" fill="${P.tool}" stroke="${plateFill}" stroke-width="3"/>`;
    if (variant==='dial') return `<circle cx="32" cy="32" r="14" stroke="${line}" ${S}/><path d="M32 32L39 21" stroke="${P.gold}" ${S}/>`;
    if (variant==='cog'){ const ticks=[0,45,90,135,180,225,270,315].map(a=>{const r=Math.PI*a/180;return `M${(32+13*Math.sin(r)).toFixed(1)} ${(32-13*Math.cos(r)).toFixed(1)}L${(32+17*Math.sin(r)).toFixed(1)} ${(32-17*Math.cos(r)).toFixed(1)}`;}).join(''); return `<circle cx="32" cy="32" r="9" stroke="${line}" ${S}/><path d="${ticks}" stroke="${line}" ${S}/>`; }
    if (variant==='three') return `<path d="M16 21h32M16 32h32M16 43h32" stroke="${line}" ${S}/>`+knob(39,21)+knob(25,32)+knob(33,43);
    return `<path d="M16 26h32M16 38h32" stroke="${line}" ${S}/>`+knob(38,26)+knob(26,38);
  });
}
// AQUARIUS APPS — the colour mark (chosen). ('mono' / 'badge' not chosen)
export function apps(size, variant='color', shadow=true, theme='midnight'){
  return icon(size,'ap'+variant,theme,shadow,({P,line,id,extra})=>{
    extra.defs = `<linearGradient id="gA${id}" x1="14" y1="54" x2="50" y2="12" gradientUnits="userSpaceOnUse"><stop stop-color="${P.line[0]}"/><stop offset="1" stop-color="${P.line[1]}"/></linearGradient><linearGradient id="gW${id}" x1="20" y1="40" x2="44" y2="40" gradientUnits="userSpaceOnUse"><stop stop-color="${P.gold}"/><stop offset="1" stop-color="${P.line[0]}"/></linearGradient>`;
    if (variant==='mono'){ const m=markPaths(32,33,0.82); return `<path d="${m.A}" stroke="${P.tool}" ${S}/><path d="${m.wave}" stroke="${P.gold}" ${S}/>`; }
    if (variant==='badge'){ const m=markPaths(28,29,0.66); return `<path d="${m.A}" stroke="url(#gA${id})" ${S}/><path d="${m.wave}" stroke="url(#gW${id})" ${S}/><rect x="43" y="43" width="10" height="10" rx="3" fill="${P.gold}"/>`; }
    const m=markPaths(32,33,0.82); return `<path d="${m.A}" stroke="url(#gA${id})" ${S}/><path d="${m.wave}" stroke="url(#gW${id})" ${S}/>`;
  });
}
// WELCOME — a gold sun over the wave (chosen). ('steps' / 'door' not chosen)
export function welcome(size, variant='sun', shadow=true, theme='midnight'){
  return icon(size,'we'+variant,theme,shadow,({P,line})=>
    variant==='steps' ? `<path d="M27 20h21M27 32h21M27 44h21" stroke="${line}" ${S}/><path d="M15 20.5l3.5 3.5 6-6" stroke="${P.gold}" ${S}/>`
    : variant==='door' ? `<path d="M20 50V17a3 3 0 0 1 3-3h18a3 3 0 0 1 3 3v33" stroke="${line}" ${S}/><circle cx="37" cy="33" r="3.5" fill="${P.gold}"/>`
    : `<circle cx="32" cy="23" r="7.5" fill="${P.gold}"/><path d="${ICON_WAVE_Y(44)}" stroke="${line}" ${S}/>`);
}
// (Check for Update has no icon of its own — Royce, 2026-09-06: it lives in System Settings and the logo menu.)
// INSTALL / REMOVE DAVINCI RESOLVE — "DR" in Sora 700 outlined to paths, a gold plus / minus centred below (chosen).
const DR = outlineText('DR', { em:27, baseline:35, cx:32, wght:700 });
export function resolve(size, verb='install', variant='dr', shadow=true, theme='midnight'){
  return icon(size,'rs'+variant+verb,theme,shadow,({P,line})=>{
    const badge = verb==='remove' ? `<path d="M27 46h10" stroke="${P.gold}" ${S}/>` : `<path d="M32 41v10M27 46h10" stroke="${P.gold}" ${S}/>`;
    if (variant==='drw')  return `<path d="${DR.d}" fill="${P.tool}"/>` + badge;
    if (variant==='tile') return `<rect x="15" y="15" width="34" height="34" rx="9" stroke="${line}" ${S}/>` + (verb==='remove' ? `<path d="M25 32h14" stroke="${P.gold}" ${S}/>` : `<path d="M32 25v14M25 32h14" stroke="${P.gold}" ${S}/>`);
    if (variant==='wave') return (verb==='remove' ? `<path d="M24 16l16 16M40 16L24 32" stroke="${P.gold}" ${S}/>` : `<path d="M32 13v20M23 24l9 9 9-9" stroke="${P.gold}" ${S}/>`) + `<path d="${ICON_WAVE_Y(45)}" stroke="${line}" ${S}/>`;
    return `<path d="${DR.d}" fill="${line}"/>` + badge;
  });
}
// Third-party stand-in — their own mark ships; never redrawn.
export function own(label,size,dark){
  return `<div style="width:${size}px;height:${size}px;border-radius:25%;display:flex;align-items:center;justify-content:center;border:1px dashed ${dark?'rgba(237,239,247,.3)':'rgba(20,23,38,.3)'};color:${dark?T.text3:T.L.text3};font:600 ${Math.max(9,Math.round(size*0.28))}px Sora,system-ui,sans-serif">${label}</div>`;
}
// the finished set, by icon name, per theme
export const SET = {
  'aquarius-editor':(s,t)=>editor(s,'simple',true,t), 'aquarius-writer':(s,t)=>writer(s,true,t), 'aquarius-files':(s,t)=>files(s,'outline',true,t),
  'aquarius-settings':(s,t)=>settings(s,'two',true,t), 'aquarius-apps':(s,t)=>apps(s,'color',true,t), 'aquarius-welcome':(s,t)=>welcome(s,'sun',true,t),
  'aquarius-install-resolve':(s,t)=>resolve(s,'install','dr',true,t), 'aquarius-remove-resolve':(s,t)=>resolve(s,'remove','dr',true,t),
};
