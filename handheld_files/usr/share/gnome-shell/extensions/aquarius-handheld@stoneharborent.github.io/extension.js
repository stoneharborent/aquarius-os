// =============================================================================
// AquariusOS Handheld — GNOME, sized for a 7-inch screen and a thumb
// =============================================================================
// HANDHELD IMAGE ONLY (handheld_files/, copied by build_files/78-handheld.sh).
//
// The Ally X's panel is 1920x1080 and GNOME runs it at 200 %, so the desktop is
// 960x540 in GNOME's own units. Two of GNOME's own layouts are wrong for that
// shape, and this fixes both:
//
// 1. THE APP GRID (bench, Royce, 2026-10-04 — twice)
//
//    For a wide, short space GNOME always picks 3 rows of 8 and shrinks the
//    icons to its 32-point size. Version 1.0 of this file asked for 2 rows of
//    5, which landed on 64 points — better, and still too small to read or to
//    aim at with a thumbstick. Royce: twice as big again.
//
//    128 points will not fit twice in the height the overview leaves under its
//    search box, workspace strip and dock, and GNOME's own size list stops at
//    96 anyway. So: ONE row of five, at a fixed 128 points. The grid becomes a
//    strip you page through left and right — the D-pad does it on the
//    desktop (arrow keys) and Y opens the app, the way a console's library
//    works.
//
// 2. THE ON-SCREEN KEYBOARD (bench, 2026-10-04)
//
//    a) Dead space. GNOME makes the keyboard a third of the screen tall and
//       then keeps the keys at their natural shape, centred. On a 960x540
//       screen that is a keyboard about 540 wide with 200 empty points either
//       side. Here the keys fill the whole width, and the keyboard is a little
//       taller (42 % of the screen instead of 33 %), so every key is wider AND
//       taller.
//    b) No way to put it away with a finger. A swipe DOWN across the keyboard
//       now closes it. (A one-finger swipe UP from the bottom edge still opens
//       it — that one is GNOME's.)
//
// HOW, AND WHAT IS PRIVATE
//
//   * The grid: setGridModes() is public; the fixed-icon-size property is a
//     declared GObject property. Reaching the grid at all goes through
//     Main.overview._overview._controls._appDisplay._grid, which is private.
//   * The keyboard: Keyboard is exported by GNOME's keyboard.js; its
//     _relayout() and the _aspectContainer inside it are private.
//
// Everything private is guarded: if a GNOME release renames something, that
// part simply does nothing and GNOME's own behaviour comes back — the overview
// and the keyboard never break. metadata.json's shell-version makes every
// GNOME bump a deliberate re-check.
// =============================================================================

import Clutter from 'gi://Clutter';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as KeyboardUI from 'resource:///org/gnome/shell/ui/keyboard.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

// ---- the app grid -----------------------------------------------------------
const HANDHELD_GRID = [{rows: 1, columns: 5}];
const HANDHELD_ICON_SIZE = 128;

// ---- the keyboard -----------------------------------------------------------
// Share of the screen's height the keyboard takes in landscape (GNOME: 1/3).
const KEYBOARD_HEIGHT_SHARE = 0.42;
// A ratio no real keyboard reaches: GNOME's AspectContainer then never narrows
// the keys to their natural shape, so they fill the width.
const FILL_RATIO = 1000;
// How far down a finger has to travel, in points, to close the keyboard.
const SWIPE_CLOSE_DISTANCE = 60;

function appGrid() {
    return Main.overview?._overview?._controls?._appDisplay?._grid ?? null;
}

export default class AquariusHandheldExtension extends Extension {
    enable() {
        this._enableGrid();
        this._enableKeyboard();
    }

    disable() {
        this._disableKeyboard();
        this._disableGrid();
    }

    // -------------------------------------------------------------------------
    _enableGrid() {
        const grid = appGrid();
        if (!grid?.setGridModes) {
            console.warn('aquarius-handheld: the app grid was not where GNOME 50 keeps it; leaving it alone');
            return;
        }
        grid.setGridModes(HANDHELD_GRID);
        if (grid.layout_manager && 'fixed_icon_size' in grid.layout_manager)
            grid.layout_manager.fixed_icon_size = HANDHELD_ICON_SIZE;
    }

    _disableGrid() {
        const grid = appGrid();
        if (grid?.layout_manager && 'fixed_icon_size' in grid.layout_manager)
            grid.layout_manager.fixed_icon_size = -1;
        grid?.setGridModes?.(null);
    }

    // -------------------------------------------------------------------------
    _enableKeyboard() {
        const proto = KeyboardUI.Keyboard?.prototype;
        if (!proto || typeof proto._relayout !== 'function') {
            console.warn('aquarius-handheld: GNOME\'s keyboard is not shaped as in GNOME 50; leaving it alone');
            return;
        }

        const originalRelayout = proto._relayout;
        this._originalRelayout = originalRelayout;

        proto._relayout = function () {
            originalRelayout.call(this);

            const monitor = Main.layoutManager.keyboardMonitor;
            if (!monitor || monitor.width <= monitor.height)
                return;

            const [minHeight] = this.get_preferred_height(-1);
            this.height = Math.clamp(monitor.height * KEYBOARD_HEIGHT_SHARE,
                minHeight, monitor.height / 2);

            fillWidth(this);
            addSwipeToClose(this);
        };

        // The keyboard may already exist (it is made the first time it is
        // needed): bring it up to date now rather than at its next relayout.
        const keyboard = Main.keyboard?.keyboardActor;
        if (keyboard)
            keyboard._relayout();
    }

    _disableKeyboard() {
        const proto = KeyboardUI.Keyboard?.prototype;
        if (proto && this._originalRelayout)
            proto._relayout = this._originalRelayout;
        this._originalRelayout = null;

        const keyboard = Main.keyboard?.keyboardActor;
        if (keyboard) {
            removeSwipeToClose(keyboard);
            unfillWidth(keyboard);
            keyboard._relayout?.();
        }
    }
}

// The keys sit in GNOME's AspectContainer, which keeps them at the layout's own
// width:height and centres them. Give it a ratio so wide that it never narrows
// them, and keep GNOME from putting the real ratio back on every layout change.
function fillWidth(keyboard) {
    const container = keyboard._aspectContainer;
    if (!container || container._aquariusFill)
        return;
    container._aquariusFill = {setRatio: container.setRatio};
    container.setRatio = function () {
        this._ratio = FILL_RATIO;
        this.queue_relayout();
    };
    container.setRatio();
}

function unfillWidth(keyboard) {
    const container = keyboard._aspectContainer;
    if (!container?._aquariusFill)
        return;
    // Drop our own setRatio so the class's comes back; GNOME sets the real
    // ratio again at its next layout change.
    delete container.setRatio;
    delete container._aquariusFill;
}

// A vertical pan across the keyboard, seen in the CAPTURE phase so it wins over
// the key under the finger: once it is recognised, that key's press is
// cancelled and nothing is typed.
function addSwipeToClose(keyboard) {
    if (keyboard._aquariusSwipe)
        return;
    const gesture = new Clutter.PanGesture({pan_axis: Clutter.PanAxis.Y});
    gesture.set_begin_threshold(SWIPE_CLOSE_DISTANCE / 2);
    gesture.connect('end', () => {
        const delta = gesture.get_accumulated_delta();
        if (delta.y >= SWIPE_CLOSE_DISTANCE && Math.abs(delta.y) > Math.abs(delta.x))
            keyboard.close(true);
    });
    keyboard.add_action_full('aquarius-swipe-down-to-close',
        Clutter.EventPhase.CAPTURE, gesture);
    keyboard._aquariusSwipe = gesture;
}

function removeSwipeToClose(keyboard) {
    if (!keyboard._aquariusSwipe)
        return;
    keyboard.remove_action(keyboard._aquariusSwipe);
    delete keyboard._aquariusSwipe;
}
