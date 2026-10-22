import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import Clutter from 'gi://Clutter';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';
import {Extension, InjectionManager} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';

export default class InstallerExtension extends Extension {
    enable() {
        // Scale for the actual panel, not just the 1280px VM used initially.
        // Keep the installer at roughly the same readable logical width.
        this._interfaceSettings = new Gio.Settings({schema_id: 'org.gnome.desktop.interface'});
        this._keyboardOverrides = new InjectionManager();
        const keyboard = Main.keyboard.keyboardActor;
        if (keyboard?._aspectContainer) {
            // GNOME 50 constrains the key grid independently of the outer
            // keyboard actor. Override both, including layout/language changes.
            const resize = () => this._sizeKeyboard();
            this._keyboardOverrides.overrideMethod(keyboard, '_relayout', original =>
                function (...args) {
                    original.apply(this, args);
                    resize();
                });
            this._keyboardOverrides.overrideMethod(keyboard._aspectContainer, 'setRatio', original =>
                function (width, height) {
                    const monitor = Main.layoutManager.keyboardMonitor ?? Main.layoutManager.primaryMonitor;
                    if (monitor) {
                        width = monitor.width;
                        height = Math.floor(monitor.height * 0.55);
                    }
                    original.call(this, width, height);
                });
        }
        this._sizeInstaller();
        this._monitorSignal = Main.layoutManager.connect('monitors-changed',
            () => this._sizeInstaller());
        this._keyboardSizeSignal = Main.keyboard.keyboardActor.connect('notify::height',
            () => this._sizeKeyboard());
        this._visibilitySignal = Main.keyboard.connect('visibility-changed', () => {
            if (Main.keyboard.visible)
                this._refreshSelection();
            else
                this._cancelClick();
        });
        const seat = global.stage.context.get_backend().get_default_seat();
        this._virtualTouch = seat.create_virtual_device(Clutter.InputDeviceType.TOUCHSCREEN_DEVICE);
        this._virtualKeyboard = seat.create_virtual_device(Clutter.InputDeviceType.KEYBOARD_DEVICE);
        this._controllerActions = new Map();
        const commands = ['up', 'down', 'left', 'right', 'select', 'dpadUp', 'dpadDown', 'dpadLeft', 'dpadRight'];
        commands.forEach((command, i) => {
            const action = global.display.grab_accelerator(`F${1 + i}`, Meta.KeyBindingFlags.IGNORE_AUTOREPEAT);
            if (action === Meta.KeyBindingAction.NONE) throw new Error('Cannot reserve installer controller key F'+(1+i));
            Main.wm.allowKeybinding(Meta.external_binding_name_for_action(action), Shell.ActionMode.NORMAL);
            this._controllerActions.set(action, command);
        });
        this._title = new PanelMenu.Button(0, 'AquariusOS Setup', true);
        this._title.reactive = false;
        this._title.can_focus = false;
        this._title.add_child(new St.Label({text: 'AquariusOS Setup',
            y_align: Clutter.ActorAlign.CENTER, style: 'font-size: 18px; padding: 0 16px;'}));
        Main.panel.addToStatusArea('aquarius-installer-title', this._title, 0, 'left');
        // Keep the text field focused while the user taps the keyboard button.
        this._button = new PanelMenu.Button(0, 'Show or hide keyboard', true);
        this._button.can_focus = false;
        this._button.add_child(new St.Label({
            text: 'Keyboard · Menu',
            y_align: Clutter.ActorAlign.CENTER,
            style: 'font-size: 18px; padding: 8px 16px;',
        }));
        this._button.connect('button-press-event', () => {
            this._toggleKeyboard();
            return Clutter.EVENT_STOP;
        });
        this._button.connect('touch-event', (_actor, event) => {
            if (event.type() === Clutter.EventType.TOUCH_BEGIN)
                this._toggleKeyboard();
            return Clutter.EVENT_STOP;
        });
        Main.panel.addToStatusArea('aquarius-installer-keyboard', this._button);

        // InputPlumber maps the controller Menu button to F12 in this ISO only.
        this._action = global.display.grab_accelerator('F12', Meta.KeyBindingFlags.IGNORE_AUTOREPEAT);
        if (this._action === Meta.KeyBindingAction.NONE)
            throw new Error('The installer could not reserve the keyboard shortcut');
        this._binding = Meta.external_binding_name_for_action(this._action);
        Main.wm.allowKeybinding(this._binding, Shell.ActionMode.NORMAL);
        this._acceleratorSignal = global.display.connect('accelerator-activated',
            (_display, action) => {
                if (this._controllerActions.has(action))
                    this._controller(this._controllerActions.get(action));
                if (action === this._action)
                    this._toggleKeyboard();
            });
        // GTK reports the text cursor through Wayland even when focus came
        // from a controller. GNOME normally waits for a touchscreen gesture.
        this._cursorSignal = Main.inputMethod.connect('cursor-location-changed', () => {
            if (this._focusIdle)
                GLib.source_remove(this._focusIdle);
            this._focusIdle = GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
                this._focusIdle = 0;
                if (Main.inputMethod.currentFocus &&
                    Main.inputMethod.currentFocus !== this._hiddenFocus)
                    Main.keyboard.open(Main.layoutManager.focusIndex);
                return GLib.SOURCE_REMOVE;
            });
        });
        this._panelSignal = Main.inputMethod.connect('input-panel-state', () => {
            if (!Main.inputMethod.currentFocus)
                this._hiddenFocus = null;
        });
        // The Fedora installer normally relies on Kiosk to maximize its window.
        this._mapSignal = global.window_manager.connect('map', (_wm, actor) => {
            const window = actor.meta_window;
            if (window.get_window_type() === Meta.WindowType.NORMAL)
                window.maximize();
        });
    }

    _sizeInstaller() {
        const monitor = Main.layoutManager.primaryMonitor;
        if (!monitor) return;
        const scale = Math.max(1.8, Math.min(3, monitor.width / 1280 * 1.8));
        this._interfaceSettings.set_double('text-scaling-factor', scale);
        this._interfaceSettings.set_int('cursor-size', Math.round(40 * scale / 1.5));
        this._sizeKeyboard();
    }

    _sizeKeyboard() {
        const monitor = Main.layoutManager.keyboardMonitor ?? Main.layoutManager.primaryMonitor;
        const keyboard = Main.keyboard.keyboardActor;
        if (!monitor || !keyboard) return;
        // A full-width key grid uses 55% of a handheld screen. The input method
        // continues to move the focused entry above the keyboard.
        const height = Math.floor(monitor.height * 0.55);
        keyboard.width = monitor.width;
        if (keyboard.height !== height) keyboard.height = height;
        keyboard._aspectContainer?.setRatio(monitor.width, height);
    }

    _controllerKeys() {
        const keys = [];
        const visit = actor => {
            if (actor.has_style_class_name?.('keyboard-key') && actor.is_mapped()) {
                const [x, y] = actor.get_transformed_position();
                const [width, height] = actor.get_transformed_size();
                keys.push({actor, x: x + width / 2, y: y + height / 2});
            }
            for (const child of actor.get_children()) visit(child);
        };
        if (Main.keyboard.keyboardActor) visit(Main.keyboard.keyboardActor);
        return keys;
    }

    _refreshSelection() {
        const keys = this._controllerKeys();
        let selected = keys.find(k => k.actor === this._selectedKey);
        if (!selected && this._keyPosition) {
            const [x, y] = this._keyPosition;
            selected = keys.reduce((best, k) => !best ||
                Math.hypot(k.x - x, k.y - y) < Math.hypot(best.x - x, best.y - y) ? k : best, null);
        }
        selected ??= keys[0];
        if (selected) this._selectKey(selected, keys);
        return selected;
    }

    _selectKey(selected, keys = this._controllerKeys()) {
        for (const key of keys) key.actor.remove_style_pseudo_class('focus');
        this._selectedKey = selected.actor;
        this._keyPosition = [selected.x, selected.y];
        selected.actor.add_style_pseudo_class('focus');
    }

    _controller(direction) {
        if (!Main.keyboard.visible) {
            const symbol = {up: Clutter.KEY_Tab, down: Clutter.KEY_Tab,
                left: Clutter.KEY_Left, right: Clutter.KEY_Right, select: Clutter.KEY_space,
                dpadUp: Clutter.KEY_Up, dpadDown: Clutter.KEY_Down,
                dpadLeft: Clutter.KEY_Left, dpadRight: Clutter.KEY_Right}[direction];
            const time = GLib.get_monotonic_time();
            if (direction === 'up') this._virtualKeyboard.notify_keyval(time, Clutter.KEY_Shift_L, Clutter.KeyState.PRESSED);
            this._virtualKeyboard.notify_keyval(time, symbol, Clutter.KeyState.PRESSED);
            this._virtualKeyboard.notify_keyval(time, symbol, Clutter.KeyState.RELEASED);
            if (direction === 'up') this._virtualKeyboard.notify_keyval(time, Clutter.KEY_Shift_L, Clutter.KeyState.RELEASED);
            return;
        }
        direction = {dpadUp: 'up', dpadDown: 'down', dpadLeft: 'left', dpadRight: 'right'}[direction] ?? direction;
        const keys = this._controllerKeys();
        let selected = this._refreshSelection();
        if (!selected) return;
        if (direction === 'select') {
            this._clickKey(selected);
            return;
        }
        const horizontal = direction === 'left' || direction === 'right';
        const sign = direction === 'left' || direction === 'up' ? -1 : 1;
        const candidates = keys.filter(k => k !== selected &&
            sign * ((horizontal ? k.x - selected.x : k.y - selected.y)) > 1);
        candidates.sort((a, b) => {
            const score = k => Math.abs(horizontal ? k.y - selected.y : k.x - selected.x) * 4 +
                Math.abs(horizontal ? k.x - selected.x : k.y - selected.y);
            return score(a) - score(b);
        });
        selected = candidates[0] ?? selected;
        this._selectKey(selected, keys);
    }

    _cancelClick() {
        if (this._clickTimer) GLib.source_remove(this._clickTimer);
        this._clickTimer = 0;
    }

    _clickKey(key) {
        if (this._clickTimer) return;
        // Native touch activates the real GNOME key without moving a pointer
        // or moving input focus away from the installer's text field.
        this._clickTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 50, () => {
            this._clickTimer = 0;
            if (!Main.keyboard.visible) return GLib.SOURCE_REMOVE;
            const current = this._controllerKeys().find(k => k.actor === key.actor);
            if (!current || Math.abs(key.x - current.x) >= 2 || Math.abs(key.y - current.y) >= 2)
                return GLib.SOURCE_REMOVE;
            const picked = global.stage.get_actor_at_pos(Clutter.PickMode.REACTIVE, key.x, key.y);
            if (!picked || (picked !== key.actor && !key.actor.contains(picked)))
                return GLib.SOURCE_REMOVE;
            this._touchActive = true;
            this._virtualTouch.notify_touch_down(GLib.get_monotonic_time(), 0, key.x, key.y);
            this._virtualTouch.notify_touch_up(GLib.get_monotonic_time(), 0);
            this._touchActive = false;
            // Let the native event handlers switch keyboard pages first.
            this._clickTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 50, () => {
                this._clickTimer = 0;
                if (Main.keyboard.visible) this._refreshSelection();
                return GLib.SOURCE_REMOVE;
            });
            return GLib.SOURCE_REMOVE;
        });
    }

    _toggleKeyboard() {
        if (Main.keyboard.visible) {
            this._cancelClick();
            this._hiddenFocus = Main.inputMethod.currentFocus;
            Main.keyboard.close();
        } else {
            this._hiddenFocus = null;
            Main.keyboard.open(Main.layoutManager.focusIndex);
        }
    }

    disable() {
        this._keyboardOverrides?.clear();
        if (this._monitorSignal) Main.layoutManager.disconnect(this._monitorSignal);
        if (this._keyboardSizeSignal)
            Main.keyboard.keyboardActor.disconnect(this._keyboardSizeSignal);
        if (this._visibilitySignal) Main.keyboard.disconnect(this._visibilitySignal);
        this._title?.destroy();
        this._cancelClick();
        if (this._touchActive)
            this._virtualTouch?.notify_touch_up(GLib.get_monotonic_time(), 0);
        this._touchActive = false;
        this._virtualTouch = null;
        this._virtualKeyboard = null;
        for (const action of this._controllerActions?.keys() ?? []) {
            global.display.ungrab_accelerator(action);
            Main.wm.allowKeybinding(Meta.external_binding_name_for_action(action), Shell.ActionMode.NONE);
        }
        if (this._panelSignal)
            Main.inputMethod.disconnect(this._panelSignal);
        if (this._focusIdle)
            GLib.source_remove(this._focusIdle);
        if (this._cursorSignal)
            Main.inputMethod.disconnect(this._cursorSignal);
        if (this._acceleratorSignal)
            global.display.disconnect(this._acceleratorSignal);
        if (this._action)
            global.display.ungrab_accelerator(this._action);
        if (this._binding)
            Main.wm.allowKeybinding(this._binding, Shell.ActionMode.NONE);
        if (this._mapSignal)
            global.window_manager.disconnect(this._mapSignal);
        this._button?.destroy();
        this._button = null;
    }
}
