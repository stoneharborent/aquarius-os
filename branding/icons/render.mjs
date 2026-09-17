// ==============================================================================
// Draw every AquariusOS app icon, in both themes, as an SVG file
// ==============================================================================
// You almost certainly do not want to run this by hand. Run
//
//     bash branding/render-app-icons.sh
//
// instead — that runs this script AND turns the results into the two icon
// themes the operating system actually ships. This file on its own only writes
// the master drawings next to itself.
//
// WHAT IT WRITES
//   branding/icons/midnight/<name>.svg    the dark set
//   branding/icons/ice/<name>.svg         the light set
//
// TEN FILES IN EACH, NOT NINE. There are nine icons; one of them is filed under
// two names: the app-chooser drawing also ships as "aquarius-installer",
// because Aquarius Installer and Aquarius Apps are two faces of one idea and
// only one of them is visible in the app grid. See ALIASES below.
//
// UNTIL 2026-09-17 there were thirteen. The Files, Settings and Console
// drawings were also written under GNOME's own identifiers (org.gnome.Nautilus,
// org.gnome.Settings, org.gnome.Ptyxis), which is how a theme replaces the icon
// of a program it does not own. Royce decided the stock GNOME apps keep their
// stock icons, so those three names are gone and GNOME's own artwork shows
// through Inherits=Adwaita. The three drawings still exist under our own names
// for our own windows to use.
//
// OPTIONS (used by branding/render-app-icons.sh, not normally by a person)
//   --size N      draw at N pixels instead of 1024
//   --out DIR     write into DIR/<theme>/<name>.svg instead of next to this file
// ==============================================================================
import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { SET } from './icons.mjs';

// ------------------------------------------------------------------------------
// The names each icon ships under
// ------------------------------------------------------------------------------
// The left-hand name is the drawing (a key in SET, in icons.mjs). The right-hand
// list is every file name it is written out as.
//
// ⚠️ NO GNOME NAMES HERE, ON PURPOSE (2026-09-17). A theme replaces a program's
// icon by filing a drawing under the name that program asks for — Files asks for
// `org.gnome.Nautilus`, Settings for `org.gnome.Settings`, the Console for
// `org.gnome.Ptyxis`. Adding one of those names to a list below would put our
// drawing on a stock GNOME app again, which is exactly what was removed. The
// stock apps keep GNOME's own icons.
const ALIASES = {
  'aquarius-editor': ['aquarius-editor'],
  'aquarius-writer': ['aquarius-writer'],
  'aquarius-files': ['aquarius-files'],
  'aquarius-settings': ['aquarius-settings'],
  'aquarius-console': ['aquarius-console'],
  // ⚠️ TWO NAMES, ONE DRAWING (2026-09-09). Aquarius Installer is the OS's
  // "install anything" window and Aquarius Apps is the first-login chooser
  // behind it — the same idea wearing two hats, and only the Installer is
  // visible in the app grid now. Rather than draw a second, nearly identical
  // plate, the same picture ships under both names: one drawing, more than one
  // thing asking for it. When the Installer gets a drawing of its own, this
  // line loses its second name and gains an entry in SET.
  'aquarius-apps': ['aquarius-apps', 'aquarius-installer'],
  'aquarius-welcome': ['aquarius-welcome'],
  'aquarius-install-resolve': ['aquarius-install-resolve'],
  'aquarius-remove-resolve': ['aquarius-remove-resolve'],
};

export const THEMES = ['midnight', 'ice'];
export const FILE_NAMES = Object.values(ALIASES).flat().sort();

// ------------------------------------------------------------------------------
// Read the options
// ------------------------------------------------------------------------------
const args = process.argv.slice(2);
const opt = (flag, fallback) => {
  const i = args.indexOf(flag);
  return i === -1 ? fallback : args[i + 1];
};
const size = Number(opt('--size', 1024));
const outRoot = opt('--out', dirname(fileURLToPath(import.meta.url)));

if (!Number.isInteger(size) || size < 8 || size > 4096) {
  console.error(`render.mjs: --size ${opt('--size')} is not a whole number of pixels between 8 and 4096.`);
  process.exit(1);
}

// ------------------------------------------------------------------------------
// Draw them
// ------------------------------------------------------------------------------
// Every drawing in icons.mjs is a function of (size, theme). Nothing about the
// SHAPE changes between the two themes — only the colours — which is the whole
// point of keeping one source: an icon cannot end up subtly different in dark
// mode because somebody edited one copy.
let written = 0;
for (const theme of THEMES) {
  const dir = join(outRoot, theme);
  mkdirSync(dir, { recursive: true });
  for (const [drawing, names] of Object.entries(ALIASES)) {
    const draw = SET[drawing];
    if (!draw) {
      console.error(`render.mjs: icons.mjs has no drawing called "${drawing}". ` +
                    'Either the name changed in icons.mjs or ALIASES above is out of date.');
      process.exit(1);
    }
    const svg = draw(size, theme);
    for (const name of names) {
      writeFileSync(join(dir, `${name}.svg`), svg);
      written++;
    }
  }
}

console.log(`render.mjs: wrote ${written} SVG files at ${size}px ` +
            `(${FILE_NAMES.length} per theme, ${THEMES.length} themes) into ${outRoot}`);
