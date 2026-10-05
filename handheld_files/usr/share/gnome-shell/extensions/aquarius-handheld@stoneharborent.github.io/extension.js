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
// 3. THE STICK RINGS (Royce, 2026-10-05)
//
//    A "Rings" switch in the quick settings menu, next to the Keyboard
//    brightness slider: the switch turns the rings off and back on, and its
//    menu picks a colour or an effect. Like the Mac-or-Windows switch, it
//    decides nothing itself — it reads ~/.config/aquarius/rings.conf and runs
//    `aq handheld rings <choice>`, the same command a person would type, which
//    needs no password (/usr/libexec/aquarius-ally-rings explains how).
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
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as KeyboardUI from 'resource:///org/gnome/shell/ui/keyboard.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as MessageTray from 'resource:///org/gnome/shell/ui/messageTray.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as QuickSettings from 'resource:///org/gnome/shell/ui/quickSettings.js';

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

// ---- the stick rings -------------------------------------------------------
const AQ_COMMAND = '/usr/bin/aq';
const RINGS_ICON = 'weather-clear-night-symbolic';
// [what `aq handheld rings` is told, what the menu says]. Kept in step with
// PRESETS and EFFECTS in /usr/libexec/aquarius-ally-rings.
const RING_CHOICES = [
    ['white', 'White'],
    ['blue', 'AquariusOS blue'],
    ['steam', 'Steam blue'],
    ['cyan', 'Cyan'],
    ['green', 'Green'],
    ['red', 'Red'],
    ['orange', 'Orange'],
    ['pink', 'Pink'],
    ['purple', 'Purple'],
    ['rainbow', 'Rainbow (turning)'],
    ['cycle', 'Every colour in turn'],
    ['breathe', 'Breathing'],
];
const RING_HEX = {
    white: 'ffffff', blue: '8ab4ff', steam: '1a9fff', cyan: '00e5ff', green: '00ff40',
    red: 'ff0000', orange: 'ff6000', pink: 'ff2090', purple: '8000ff',
};

function ringsConfFile() {
    return Gio.File.new_for_path(
        GLib.build_filenamev([GLib.get_user_config_dir(), 'aquarius', 'rings.conf']));
}

/** @returns {{effect: string, colour: string}} what rings.conf says, or the default */
function readRings() {
    const found = {effect: 'solid', colour: 'ffffff'};
    try {
        const [okRead, bytes] = ringsConfFile().load_contents(null);
        if (!okRead)
            return found;
        for (const line of new TextDecoder().decode(bytes).split('\n')) {
            const match = /^\s*(effect|colour)\s*=\s*([0-9A-Za-z]+)/.exec(line);
            if (match)
                found[match[1]] = match[2].toLowerCase();
        }
    } catch (_error) {
        // No file yet: the default.
    }
    return found;
}

/** Which menu entry a rings.conf choice is. */
function choiceKey({effect, colour}) {
    if (effect === 'solid')
        return Object.keys(RING_HEX).find(k => RING_HEX[k] === colour) ?? null;
    return effect;
}

function complainRings(body) {
    try {
        const source = MessageTray.getSystemSource();
        source.addNotification(new MessageTray.Notification({
            source,
            title: 'The stick rings could not be changed',
            body,
            isTransient: true,
        }));
    } catch (error) {
        console.warn(`aquarius-handheld: ${body} (and the notification failed: ${error})`);
    }
}

const RingsToggle = GObject.registerClass(
class RingsToggle extends QuickSettings.QuickMenuToggle {
    _init() {
        super._init({title: 'Rings', iconName: RINGS_ICON, toggleMode: false});

        this._cancellable = new Gio.Cancellable();
        this._items = new Map();
        this.menu.setHeader(RINGS_ICON, 'Stick rings',
            'Brightness is the Keyboard slider');
        for (const [key, label] of RING_CHOICES) {
            const item = new PopupMenu.PopupMenuItem(label);
            item.connect('activate', () => this._run(key));
            this.menu.addMenuItem(item);
            this._items.set(key, item);
        }
        this.connect('clicked', () => this._run(this.checked ? 'off' : 'on'));

        try {
            this._monitor = ringsConfFile().monitor_file(
                Gio.FileMonitorFlags.WATCH_MOVES, this._cancellable);
            this._monitor.connect('changed', () => this._refresh());
        } catch (error) {
            console.warn(`aquarius-handheld: could not watch rings.conf: ${error}`);
        }
        this._refresh();
    }

    _refresh() {
        const rings = readRings();
        const key = choiceKey(rings);
        this.checked = rings.effect !== 'off';
        const label = RING_CHOICES.find(([k]) => k === key)?.[1];
        this.subtitle = rings.effect === 'off' ? 'Off' : (label ?? `#${rings.colour}`);
        for (const [k, item] of this._items) {
            item.setOrnament(k === key
                ? PopupMenu.Ornament.CHECK : PopupMenu.Ornament.NONE);
        }
    }

    _run(choice) {
        let proc;
        try {
            proc = Gio.Subprocess.new([AQ_COMMAND, 'handheld', 'rings', choice],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
        } catch (error) {
            complainRings(`AquariusOS could not start ${AQ_COMMAND}. ${error.message}`);
            return;
        }
        proc.communicate_utf8_async(null, this._cancellable, (source, result) => {
            try {
                const [, , stderr] = source.communicate_utf8_finish(result);
                if (!source.get_successful())
                    complainRings((stderr || '').trim() || `'aq handheld rings ${choice}' did not succeed.`);
                this._refresh();
            } catch (error) {
                if (!error?.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                    complainRings(error?.message ?? String(error));
            }
        });
    }

    destroy() {
        this._cancellable.cancel();
        this._monitor?.cancel();
        this._monitor = null;
        super.destroy();
    }
});

const RingsIndicator = GObject.registerClass(
class RingsIndicator extends QuickSettings.SystemIndicator {
    _init() {
        super._init();
        this.quickSettingsItems.push(new RingsToggle());
    }

    destroy() {
        this.quickSettingsItems.forEach(item => item.destroy());
        this.quickSettingsItems.length = 0;
        super.destroy();
    }
});

export default class AquariusHandheldExtension extends Extension {
    enable() {
        this._enableGrid();
        this._enableKeyboard();
        // Only where there are rings to set (the handheld image ships both).
        if (GLib.file_test('/usr/libexec/aquarius-ally-rings', GLib.FileTest.IS_EXECUTABLE)) {
            this._rings = new RingsIndicator();
            Main.panel.statusArea.quickSettings.addExternalIndicator(this._rings);
        }
    }

    disable() {
        this._rings?.destroy();
        this._rings = null;
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
