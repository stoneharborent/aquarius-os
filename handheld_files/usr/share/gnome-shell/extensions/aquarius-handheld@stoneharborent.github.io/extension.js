// =============================================================================
// AquariusOS Handheld — an app grid you can read on a 7-inch screen
// =============================================================================
// HANDHELD IMAGE ONLY (handheld_files/, copied by build_files/78-handheld.sh).
//
// WHY (bench photo, Royce, 2026-10-04)
//
// The Ally X's panel is 1920x1080 and GNOME runs it at 200 %, so the desktop is
// 960x540 in GNOME's own units. The app grid picks its shape from the space it
// has, and for a wide, short space it always picks 3 rows of 8 — then shrinks
// the icons until three rows fit between the search box, the workspace previews
// and the dock. On this screen that is GNOME's 32-point size: icons too small to
// read, and too small to aim at with a thumbstick.
//
// Two rows of five give each icon about twice the room, which on the same
// screen lands on the 64-point size. Fewer apps per page, more pages; the
// D-pad (arrow keys on the desktop) and Y (Enter) move between them and open
// one, exactly as a keyboard does.
//
// HOW. GNOME's grid has a public setGridModes() for this — its own folder
// popups use it to ask for 3x3. Handing it a single mode leaves it no other
// choice. Disabling hands it null, which puts GNOME's own list back.
//
// ⚠️ THE ONE PRIVATE PATH. Main.overview._overview._controls._appDisplay._grid
// is how the app grid is reached; GNOME offers no public name for it. If a
// GNOME release renames any step, this does NOTHING (the guard below) rather
// than breaking the overview — the grid simply goes back to small icons, and
// metadata.json's shell-version means it is re-checked on every GNOME bump.
// =============================================================================

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const HANDHELD_GRID = [{rows: 2, columns: 5}];

function appGrid() {
    return Main.overview?._overview?._controls?._appDisplay?._grid ?? null;
}

export default class AquariusHandheldExtension extends Extension {
    enable() {
        const grid = appGrid();
        if (grid?.setGridModes)
            grid.setGridModes(HANDHELD_GRID);
        else
            console.warn('aquarius-handheld: the app grid was not where GNOME 50 keeps it; leaving it alone');
    }

    disable() {
        appGrid()?.setGridModes?.(null);
    }
}
