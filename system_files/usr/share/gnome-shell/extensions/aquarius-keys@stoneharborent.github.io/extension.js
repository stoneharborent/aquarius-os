// =============================================================================
// Mac or Windows — the AquariusOS quick-settings switch
// =============================================================================
// WHAT THIS IS
//
// A small GNOME Shell add-on, written by us, that puts ONE switch in the menu
// at the top-right corner of the screen — the same menu that holds Wi-Fi,
// Bluetooth and Dark Style. The switch is the Mac-or-Windows choice:
//
//   Mac       Copy is Command-C, and the window buttons sit on the LEFT
//   Windows   Copy is Control-C, and the window buttons sit on the RIGHT
//
// Before this existed, the only two ways to change that were the Welcome
// window (which you see once, on your first login) and typing a command in a
// terminal. Royce asked for a graphical switch on 2026-09-16, and this is the
// GNOME half of the answer. The KDE Plasma half is a page in System Settings —
// see kcm/aquarius-keys/ in this repo.
//
// ------------------------------------------------------------------------------
// ⚠️ THIS FILE DOES NOT DECIDE ANYTHING. IT ASKS AND IT TELLS.
// ------------------------------------------------------------------------------
// There is exactly one program that owns this setting: /usr/bin/aq. This add-on
//
//   * READS the same file aq reads — ~/.config/aquarius/keys.conf — to know
//     which mode is on, and treats a missing file as Mac, because that is the
//     AquariusOS default and aq says the same;
//   * WRITES nothing. To change the mode it runs `aq keys mac` or
//     `aq keys windows`, exactly as a person would type it.
//
// That is deliberate. `aq keys` does four things beyond writing one line —
// restarts the remapper, moves GNOME's window buttons, moves KDE's window
// buttons, and tells a running KWin to re-read them. An add-on that wrote the
// file itself would do one of those four and look broken.
//
// ------------------------------------------------------------------------------
// ⚠️ NOTHING HERE MAY BLOCK. THIS CODE RUNS INSIDE THE DESKTOP ITSELF.
// ------------------------------------------------------------------------------
// GNOME Shell draws every window, every animation and every key press on one
// thread, and an add-on runs on that same thread. A command run the ordinary
// way — start it, wait for it to finish — would freeze the whole desktop for as
// long as it took. So `aq` is started asynchronously (Gio.Subprocess) and the
// answer arrives later in a callback. If it fails, the person gets a
// notification; this file never throws an error at the shell.
// =============================================================================

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as MessageTray from 'resource:///org/gnome/shell/ui/messageTray.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as QuickSettings from 'resource:///org/gnome/shell/ui/quickSettings.js';

// The command that owns the setting. See the header.
const AQ_COMMAND = '/usr/bin/aq';

// The icon. It is one of the symbolic icons every GNOME desktop already has,
// on purpose — design rule: we do not draw new art for a switch.
const ICON_NAME = 'input-keyboard-symbolic';

// The two modes, in the order they appear in the menu, with the words on them.
// Mac is first because Mac is the AquariusOS default everywhere else, and the
// wording matches the two cards in the Welcome window so that a person meeting
// this switch for the second time reads the same sentence.
const MODES = [
    ['mac', 'Mac', 'Copy is ⌘C. Window buttons on the left.'],
    ['windows', 'Windows', 'Copy is Ctrl+C. Window buttons on the right.'],
];

// The AquariusOS default, used whenever the file is missing or unreadable.
// ⚠️ THIS RULE IS WRITTEN IN THREE OTHER PLACES — /usr/bin/aq,
// /usr/libexec/aquarius-keys-run and the KDE page — and all four must agree.
const DEFAULT_MODE = 'mac';

/**
 * Where the answer lives: ~/.config/aquarius/keys.conf.
 *
 * GLib.get_user_config_dir() is the same folder `aq` means by
 * ${XDG_CONFIG_HOME:-$HOME/.config}, worked out the same way.
 *
 * @returns {Gio.File} the settings file, whether or not it exists yet
 */
function keysConfFile() {
    return Gio.File.new_for_path(
        GLib.build_filenamev([GLib.get_user_config_dir(), 'aquarius', 'keys.conf']));
}

/**
 * Read the mode out of that file.
 *
 * The file is a handful of lines of comments and one `mode=` line. We take the
 * LAST mode= line, which is what `aq` does too — a file somebody has
 * half-edited by hand can have two, and the two have to agree on which wins.
 *
 * Anything unexpected — no file, no permission, a mode nobody recognises —
 * means Mac, because that is the default and because a switch that shows
 * nothing at all is worse than a switch that shows the default.
 *
 * @returns {string} 'mac' or 'windows'
 */
function readMode() {
    let text;
    try {
        const [okRead, bytes] = keysConfFile().load_contents(null);
        if (!okRead)
            return DEFAULT_MODE;
        text = new TextDecoder().decode(bytes);
    } catch (_error) {
        // No file yet is the normal case on a fresh account, not a fault.
        return DEFAULT_MODE;
    }

    let found = DEFAULT_MODE;
    for (const line of text.split('\n')) {
        const match = /^\s*mode\s*=\s*([A-Za-z]+)/.exec(line);
        if (match && (match[1] === 'mac' || match[1] === 'windows'))
            found = match[1];
    }
    return found;
}

/**
 * Say something went wrong, in the notification tray, in a sentence.
 *
 * ⚠️ WHY A NOTIFICATION AND NOT A THROWN ERROR. An add-on that throws gets
 * marked as broken by GNOME and stops loading — so one bad moment would cost
 * the person the switch permanently. A notification costs them nothing.
 *
 * @param {string} body the sentence to show
 */
function complain(body) {
    try {
        const source = MessageTray.getSystemSource();
        const notification = new MessageTray.Notification({
            source,
            title: 'Keyboard style could not be changed',
            body,
            isTransient: true,
        });
        source.addNotification(notification);
    } catch (error) {
        // If even the notification machinery is unhappy, write it to the log
        // and carry on. Never take the desktop down over a message.
        console.warn(`aquarius-keys: ${body} (and the notification failed: ${error})`);
    }
}

// -----------------------------------------------------------------------------
// The switch itself
// -----------------------------------------------------------------------------
// A QuickMenuToggle is the GNOME control with two halves: press the left half
// and something happens, press the arrow on the right and a little menu opens.
// Here the left half flips to the other mode (one press, the common case) and
// the menu lists both with a tick beside the one that is on.
const AquariusKeysToggle = GObject.registerClass(
class AquariusKeysToggle extends QuickSettings.QuickMenuToggle {
    _init() {
        super._init({
            title: 'Mac-style keys',
            iconName: ICON_NAME,
            // false = pressing it does NOT flick the switch by itself. We do
            // that ourselves, only once `aq` has actually succeeded, so the
            // switch can never show a mode the computer is not really in.
            toggleMode: false,
        });

        // Everything started from here is stopped when this object is
        // destroyed. See destroy() at the bottom — GNOME's review rules are
        // strict about an add-on leaving something running after it is
        // switched off, and they are right to be.
        this._cancellable = new Gio.Cancellable();
        this._monitor = null;
        this._items = new Map();
        this._mode = DEFAULT_MODE;

        this.menu.setHeader(ICON_NAME, 'Keyboard shortcuts',
            'Which computer should this feel like?');

        for (const [mode, label, description] of MODES) {
            const item = new PopupMenu.PopupMenuItem(`${label} — ${description}`);
            item.connect('activate', () => this._choose(mode));
            this.menu.addMenuItem(item);
            this._items.set(mode, item);
        }

        // Pressing the switch means "give me the other one".
        this.connect('clicked', () =>
            this._choose(this._mode === 'mac' ? 'windows' : 'mac'));

        // ----------------------------------------------------------------------
        // Watch the file, so the switch is never out of date
        // ----------------------------------------------------------------------
        // The mode can also be changed from a terminal (`aq keys windows`), from
        // the Welcome window, or from the KDE page on the other desktop. Rather
        // than re-reading the file every few seconds, we ask the system to tell
        // us when it changes. The watch works even though the file may not exist
        // yet: being created counts as a change.
        try {
            this._monitor = keysConfFile().monitor_file(
                Gio.FileMonitorFlags.WATCH_MOVES, this._cancellable);
            this._monitor.connect('changed', () => this._refresh());
        } catch (error) {
            // Losing the watch costs us live updating, nothing more. The switch
            // still reads the file every time the menu is built and every time
            // it changes the mode itself.
            console.warn(`aquarius-keys: could not watch the settings file: ${error}`);
        }

        this._refresh();
    }

    /**
     * Read the file and make the switch say what it says.
     */
    _refresh() {
        this._mode = readMode();

        // The subtitle is the whole point of the switch being here: the answer
        // to "which one am I on?" without opening anything.
        this.subtitle = this._mode === 'mac' ? 'Mac' : 'Windows';
        this.checked = this._mode === 'mac';

        for (const [mode, item] of this._items) {
            item.setOrnament(mode === this._mode
                ? PopupMenu.Ornament.CHECK
                : PopupMenu.Ornament.NONE);
        }
    }

    /**
     * Change the mode by running `aq keys <mode>`, without blocking the shell.
     *
     * @param {string} mode 'mac' or 'windows'
     */
    _choose(mode) {
        if (mode === this._mode) {
            // Already there. Nothing to run, and running it anyway would
            // restart the remapper for no reason.
            this._refresh();
            return;
        }

        let proc;
        try {
            proc = Gio.Subprocess.new(
                [AQ_COMMAND, 'keys', mode],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
        } catch (error) {
            complain(`AquariusOS could not start ${AQ_COMMAND}. ${error.message}`);
            return;
        }

        proc.communicate_utf8_async(null, this._cancellable, (source, result) => {
            try {
                const [, , stderr] = source.communicate_utf8_finish(result);
                if (source.get_successful()) {
                    // `aq` also writes the file, which sets the watch above
                    // going — but read it back here too, so the switch is right
                    // even on a machine where the watch could not be set up.
                    this._refresh();
                } else {
                    const detail = (stderr || '').trim();
                    complain(detail || `'aq keys ${mode}' did not succeed.`);
                }
            } catch (error) {
                // Being cancelled is what happens when the add-on is switched
                // off mid-command. It is not a fault and deserves no message.
                if (error?.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                    return;
                complain(error?.message ?? String(error));
            }
        });
    }

    destroy() {
        // Stop the watch and cancel anything still in flight BEFORE the object
        // goes away, or a callback arrives later holding a dead switch.
        this._cancellable?.cancel();
        this._cancellable = null;
        this._monitor?.cancel();
        this._monitor = null;
        this._items.clear();
        super.destroy();
    }
});

// -----------------------------------------------------------------------------
// The holder GNOME wants
// -----------------------------------------------------------------------------
// GNOME does not take a switch on its own; it takes an "indicator" which
// carries one or more switches. Ours carries exactly one and no top-bar icon.
const AquariusKeysIndicator = GObject.registerClass(
class AquariusKeysIndicator extends QuickSettings.SystemIndicator {
    _init() {
        super._init();
        this.quickSettingsItems.push(new AquariusKeysToggle());
    }

    destroy() {
        this.quickSettingsItems.forEach(item => item.destroy());
        this.quickSettingsItems.length = 0;
        super.destroy();
    }
});

export default class AquariusKeysExtension extends Extension {
    enable() {
        this._indicator = new AquariusKeysIndicator();
        Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator);
    }

    disable() {
        // ⚠️ EVERYTHING GOES. GNOME switches add-ons off when the screen locks,
        // so this runs often, not just at logout — and anything left behind
        // leaks a little more every time.
        this._indicator?.destroy();
        this._indicator = null;
    }
}
