/*
 * AquariusOS Quick Settings — the Brightness slider
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Loaded by a Loader in FullRepresentation.qml. If it fails, the Brightness row
 * is absent and the rest of the panel is fine.
 *
 * ============================================================================
 * WHERE THE API BELOW COMES FROM
 * ============================================================================
 *   powerdevil, branch Plasma/6.7
 *   applets/brightness/main.qml, applets/brightness/PopupDialog.qml
 *   applets/brightness/plugin/screenbrightnesscontrol.h
 *   applets/brightness/plugin/screenbrightnessdisplaymodel.cpp
 *   https://invent.kde.org/plasma/powerdevil/-/tree/Plasma/6.7/applets/brightness
 *
 * ⚠️ TWO THINGS THE RESEARCH NOTE GOT WRONG, corrected here after reading the
 * actual source. Anybody re-checking this should know, because both mistakes
 * cost time:
 *
 *   1. The brightness applet is NOT in plasma-workspace. It lives in the
 *      `powerdevil` repository. So does the battery applet.
 *
 *   2. `ScreenBrightnessControl` has NO `brightness` property and NO
 *      `maxBrightness` property. Those exist on `KeyboardBrightnessControl`
 *      (the keyboard backlight), which is a different thing entirely. Binding
 *      to `screenBrightnessControl.brightness` gets you `undefined`, silently.
 *
 * What ScreenBrightnessControl actually has, verbatim from its header:
 *
 *   Q_PROPERTY(QAbstractListModel *displays READ displays CONSTANT)
 *   Q_PROPERTY(bool isBrightnessAvailable ...)
 *   public Q_SLOTS: void setBrightness(const QString &displayName, int value);
 *
 * and the model's roles (screenbrightnessdisplaymodel.cpp):
 *
 *   displayName, label, isInternal, brightness, maxBrightness
 *
 * ============================================================================
 * WHY THERE IS A LOOP IN A FILE THAT DRAWS ONE SLIDER
 * ============================================================================
 * Plasma 6.7 changed brightness from "the screen" to "each screen". A laptop
 * plugged into two monitors has three entries, each with its own brightness and
 * its own maximum, and `setBrightness` takes the name of the one you mean.
 *
 * The design has one slider. So this file has to choose a screen, and it
 * chooses the built-in one if there is a built-in one, because on a laptop that
 * is the screen the brightness key affects and the one a person means. If there
 * is no internal panel it takes the first display offered.
 *
 * That is a real simplification and it is worth being honest about it: on a
 * multi-monitor desktop this slider moves ONE monitor, not all of them. The
 * full per-screen controls are still one click away in the stock brightness
 * applet and in System Settings. Widening this to a slider per display is a
 * reasonable future change; it is deliberately not in the first version,
 * because the design asks for one row.
 */

import QtQuick
import org.kde.plasma.private.brightnesscontrolplugin

AqSlider {
    id: brightness

    label: i18n("Brightness")

    // The display this slider drives. Null on a machine whose monitors offer no
    // brightness control at all — most desktop monitors, which are dimmed by
    // their own physical buttons and cannot be reached from software.
    property QtObject targetDisplay: null

    available: screenBrightnessControl.isBrightnessAvailable && targetDisplay !== null

    // maxBrightness is whatever the hardware counts in — it is NOT a percentage
    // and it is NOT always 100. Dividing by it is what turns it into the 0-to-1
    // that AqSlider works in.
    value: (available && targetDisplay.maxBrightness > 0)
                ? targetDisplay.brightness / targetDisplay.maxBrightness
                : 0

    onMoved: newValue => {
        if (!available) {
            return
        }
        // Note this is a method call taking the display's NAME, not a property
        // assignment. That is the only way to set it.
        screenBrightnessControl.setBrightness(
            targetDisplay.displayName,
            Math.round(newValue * targetDisplay.maxBrightness))
    }

    ScreenBrightnessControl {
        id: screenBrightnessControl

        // `isSilent` suppresses PowerDevil's big on-screen brightness overlay.
        // It is set true here because this slider IS the on-screen feedback —
        // the popup would be a second, redundant indicator drawn on top of the
        // panel the user is already looking at. The stock applet does the same
        // thing while its own popup is open.
        isSilent: true
    }

    // -------------------------------------------------------------------------
    // Turning the model of displays into one object we can bind to
    // -------------------------------------------------------------------------
    // `displays` is a list model, and QML cannot bind straight into "row 0 of a
    // model". An Instantiator builds a small object per row — Instantiator
    // rather than Repeater because Repeater insists its delegate is something
    // visible, and these are pure data.
    //
    // Each object is then offered to `pickTarget`, which keeps the best one.
    // Because `targetDisplay` is a real property, the bindings above update by
    // themselves whenever the chosen display's brightness changes.
    Instantiator {
        id: displayInstantiator
        model: screenBrightnessControl.displays

        delegate: QtObject {
            // `required property` is how a delegate asks for a model role by
            // name. Spelling one of these wrong is a runtime error naming the
            // role, which is much easier to debug than a silent undefined.
            required property string displayName
            required property int brightness
            required property int maxBrightness
            required property bool isInternal
        }

        onObjectAdded: (index, object) => brightness.pickTarget()
        onObjectRemoved: (index, object) => brightness.pickTarget()
    }

    function pickTarget() {
        let fallback = null

        for (let i = 0; i < displayInstantiator.count; ++i) {
            const display = displayInstantiator.objectAt(i)
            if (!display) {
                continue
            }
            if (display.isInternal) {
                // The laptop panel. Stop looking.
                targetDisplay = display
                return
            }
            if (fallback === null) {
                fallback = display
            }
        }

        targetDisplay = fallback
    }

    Component.onCompleted: pickTarget()
}
