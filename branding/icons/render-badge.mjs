// Turn game-mode-badge.svg into game-mode-badge.png (512 px), the file the OS
// build composites onto Steam's icon. Only needed after editing the SVG.
//
// The PNG is written into system_files/usr/share/aquarius/branding/, next to
// the other branding pictures, because that is the folder the OS build can
// reach (the Containerfile's ctx stage copies system_files/, not branding/) —
// the same reason render-app-icons.sh writes the themes into system_files/.
//
//     npm --prefix branding/icons install
//     node branding/icons/render-badge.mjs
//
// It is a separate, tiny renderer rather than part of render.mjs because the
// badge is not one of the nine themed icons: it has no Ice/Midnight pair and
// does not ship under a theme name of its own.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import { Resvg } from '@resvg/resvg-js';

const here = dirname(fileURLToPath(import.meta.url));
const svg = readFileSync(join(here, 'game-mode-badge.svg'), 'utf8');
const out = resolve(here, '../../system_files/usr/share/aquarius/branding/game-mode-badge.png');
const png = new Resvg(svg, { fitTo: { mode: 'width', value: 512 } }).render().asPng();
writeFileSync(out, png);
console.log(`wrote ${out} (${png.length} bytes)`);
