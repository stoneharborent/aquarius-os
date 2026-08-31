/*
 * AquariusOS Quick Settings — the Sound slider
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Loaded by a Loader in FullRepresentation.qml, for the same fail-soft reason
 * the tiles are. If this file cannot load, the Sound row simply is not there
 * and everything else in the panel still works.
 *
 * ============================================================================
 * WHERE THE API BELOW COMES FROM
 * ============================================================================
 *   plasma-pa, branch Plasma/6.7, file `applet/main.qml`
 *   https://invent.kde.org/plasma/plasma-pa/-/blob/Plasma/6.7/applet/main.qml
 *   and `applet/ListItemBase.qml` for the volume arithmetic.
 *
 * ⚠️ Same path warning as the Wi-Fi tile: it is `applet/main.qml`, flat. The
 * Plasma 5 `applet/contents/ui/main.qml` path does not exist any more.
 *
 * The exact lines this file leans on:
 *
 *   import org.kde.plasma.private.volume                 (main.qml, line 21 —
 *                                                         bare, no version)
 *   PreferredDevice.sink                                 (main.qml, line 84)
 *   function volumePercent(volume) {                     (main.qml, line 132)
 *       return Math.round(volume / PulseAudio.NormalVolume * 100.0);
 *   }
 *   function setVolumeByPercent(targetPercent) {         (ListItemBase.qml, ~407)
 *       item.model.PulseObject.volume =
 *           Math.round(PulseAudio.NormalVolume * (targetPercent/100));
 *   }
 *   onMoved: { item.model.Volume = value;                (ListItemBase.qml, ~265)
 *              item.model.Muted = value === 0; }
 *
 * ============================================================================
 * ⚠️ THIS IS A `private` IMPORT — the riskiest kind
 * ============================================================================
 * `org.kde.plasma.private.volume` has `private` in its name, and that word is
 * KDE's way of saying "this is our internal plumbing, we may change or delete
 * it in any release and we owe you no warning." It is imported anyway because
 * there is no public alternative — it is the only way to reach PulseAudio from
 * QML, and it is what KDE's own volume applet uses, so it cannot disappear
 * without the stock volume control disappearing at the same moment.
 *
 * What protects us is not the import, it is the two layers around it: the
 * Loader (this file failing costs one row, not the panel) and the build check
 * (build_files/quick-settings-check.sh fails the image build if the module is
 * not installed, so a Bazzite rebase that dropped it would turn CI red before
 * anyone shipped it).
 *
 * ============================================================================
 * A DELIBERATE SIMPLIFICATION, STATED HONESTLY
 * ============================================================================
 * The stock applet builds a `SinkModel` and a `PulseObjectFilterModel` and
 * shows every output device with its own slider. This panel has ONE slider, for
 * the default output, because that is what the design draws.
 *
 * That is not a shortcut around the model — `PreferredDevice` is a proper QML
 * singleton that plasma-pa registers for exactly this purpose (registered in
 * plasma-pa's `src/qml/plugin.cpp` via `qmlRegisterSingletonType<PreferredDevice>`),
 * and `PreferredDevice.sink` is what the stock applet itself reads when it needs
 * "the current output" for its tray icon. Anybody who wants to change which
 * device is the default still does it the normal way, in the audio settings.
 */

import QtQuick
import org.kde.plasma.private.volume

AqSlider {
    id: sound

    label: i18n("Sound")

    // No sink means no working sound card. Hide the row rather than show a
    // slider that moves and does nothing.
    available: PreferredDevice.sink !== null

    // PulseAudio counts volume in its own units, where `PulseAudio.NormalVolume`
    // is 100%. AqSlider works in 0.0-to-1.0, so the two are divided/multiplied
    // on the way in and out. `NormalVolume` is asked for by name rather than
    // assumed to be 65536, because it is a PulseAudio constant and not ours.
    value: available ? PreferredDevice.sink.volume / PulseAudio.NormalVolume : 0

    onMoved: newValue => {
        if (!available) {
            return
        }
        PreferredDevice.sink.volume = Math.round(PulseAudio.NormalVolume * newValue)

        // Dragging to zero mutes, and dragging up from zero unmutes. Without
        // this, pulling the slider off zero on a muted machine changes the
        // number and produces no sound, which reads as a broken slider. The
        // stock applet does the same thing on the same event.
        PreferredDevice.sink.muted = (newValue === 0)
    }
}
