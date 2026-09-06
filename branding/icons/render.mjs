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
// TWELVE FILES IN EACH, NOT NINE. There are nine icons; three of them are filed
// under two names each, because GNOME's Files, GNOME's Settings and the terminal
// look their own icons up by their own identifiers (org.gnome.Nautilus,
// org.gnome.Settings, org.gnome.Ptyxis) and nothing will make them ask for
// "aquarius-files". So the same drawing is written twice: once under the GNOME
// name, so the icon actually appears, and once under ours, so our own windows,
// docs and the Aquarius Shell can name it without knowing anything about GNOME.
// See ALIASES below.
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
// ⚠️ THE GNOME NAMES ARE NOT DECORATION. `org.gnome.Nautilus` is how the Files
// app asks for its own icon, `org.gnome.Settings` is how the Settings app asks
// for its own, and `org.gnome.Ptyxis` is how the terminal asks for its own —
// Ptyxis is Fedora's terminal and it is the Console this image ships. Because
// our themes say `Inherits=Adwaita`, a name we do not provide falls through to
// GNOME's own artwork — so dropping any of these lines does not produce an error
// anywhere. It produces GNOME icons sitting in a dock full of Aquarius ones,
// which is the kind of thing that ships.
const ALIASES = {
  'aquarius-editor': ['aquarius-editor'],
  'aquarius-writer': ['aquarius-writer'],
  'aquarius-files': ['org.gnome.Nautilus', 'aquarius-files'],
  'aquarius-settings': ['org.gnome.Settings', 'aquarius-settings'],
  'aquarius-console': ['org.gnome.Ptyxis', 'aquarius-console'],
  'aquarius-apps': ['aquarius-apps'],
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
