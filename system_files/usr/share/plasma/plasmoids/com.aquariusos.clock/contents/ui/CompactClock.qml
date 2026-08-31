/*
    SPDX-FileCopyrightText: 2026 Stone Harbor Entertainment
    SPDX-License-Identifier: GPL-2.0-or-later
*/
// =============================================================================
// The clock as it appears in the top bar
// =============================================================================
// The design (branding/design-system/AquariusOS Desktop Shell.html, the bar item
// with onclick="toggle('notif')") is:
//
//     Sat Aug 30 21:47
//     └─ dimmer ──┘ └ normal
//
// Date first, then the time, one line, and the date drawn in the quieter colour.
// That last part is the entire reason this widget exists — see main.qml.
//
// TWO DECISIONS CARRIED OVER FROM THE LAYOUT SCRIPT, WHICH THIS REPLACES
//
//  1. THE DATE READS "ddd MMM d".  Short day, short month, day with no leading
//     zero — "Sat Aug 30". That was the customDateFormat the layout script set
//     on KDE's clock; it is the same string here, now applied by us.
//
//  2. 12-HOUR OR 24-HOUR FOLLOWS THE USER'S COUNTRY. We do NOT force 24-hour,
//     even though the design mock shows 21:47. The reasoning was written down
//     when the layout script was first built and has not changed: the choice
//     belongs to the person's locale, which they picked during setup. A German
//     install shows 21:47 and an American one shows 9:47 PM, and both are right.
//     `Qt.locale().timeFormat(Locale.ShortFormat)` is exactly that promise —
//     it returns whatever the country uses.
//
// WHY THE DATE CAN BE DIMMER HERE WHEN IT COULD NOT BE BEFORE
//   A colour scheme gives a widget more than one text colour. `textColor` is the
//   bright one; `disabledTextColor` is the quiet one. On the Plasma desktop
//   these map onto KDE's colour scheme like this:
//
//     qqc2-desktop-style/kirigami-plasmadesktop-integration/plasmadesktoptheme.cpp
//         setTextColor(...foreground(KColorScheme::NormalText)...)
//         setDisabledTextColor(...foreground(KColorScheme::InactiveText)...)
//
//   and in our own scheme, system_files/usr/share/color-schemes/AquariusDark.colors,
//   ForegroundInactive is 180,186,205 — which IS the design's `text-2` (#B4BACD).
//   So on AquariusOS this lands on the designed colour exactly, and on somebody
//   else's colour scheme it lands on whatever THEIR quiet text colour is, which
//   is the behaviour we want. We never hard-code #B4BACD.
//
//   (The design actually tints the bar date with `text-3`, one step quieter
//   still. A colour scheme has no third foreground, so `text-2` via
//   InactiveText is as close as an honest, scheme-driven answer gets. Noted in
//   docs/clock-notifications-widget.md.)
//
// A LIMIT WORTH KNOWING: this is laid out for a HORIZONTAL panel, which is where
// AquariusOS puts it. Dropped into a vertical panel it will be too wide. Fixing
// that properly means a second stacked layout; nothing in our design needs one.
// =============================================================================
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

MouseArea {
    id: compact

    // Set by main.qml; ticks once a minute.
    property date now: new Date()

    // Set by main.qml: is the popup open right now?
    property bool appletExpanded: false

    // Asks main.qml to open or close the popup. `wasOpen` is the state at the
    // moment the button went down — see the note on `wasExpanded` below.
    signal toggleRequested(bool wasOpen)

    // --- design measurements -------------------------------------------------
    // The design's bar item is `padding: 0 8px` with a 6px-radius hover wash at
    // 8% white. `smallSpacing` is Kirigami's 4px-ish step, so two of them is the
    // 8px, expressed in a way that grows if somebody enlarges the interface font.
    readonly property int horizontalPadding: Kirigami.Units.smallSpacing * 2
    readonly property int hoverRadius: 6

    // --- the two strings -----------------------------------------------------
    // Qt.locale().toString(date, "format") is how KDE's own clock applies a
    // custom date format (applets/digital-clock/DigitalClock.qml, dateFormatter).
    readonly property string dateText: Qt.locale().toString(compact.now, "ddd MMM d")

    // Locale short time, with any seconds taken back out. KDE does the same
    // trimming in DigitalClock.qml's timeFormatCorrection(), and for the same
    // reason: QLocale only offers "long" (too much) and "short" (which in some
    // countries still carries seconds), and a bar clock wants neither.
    readonly property string timeText: Qt.formatTime(compact.now, compact.timeFormat)
    readonly property string timeFormat: {
        const short = Qt.locale().timeFormat(Locale.ShortFormat);
        // Pull out "hours", whatever sits between, and "minutes"; drop the rest.
        const match = /(hh?)(.+?)(mm)/i.exec(short);
        if (!match) {
            // No locale we know of fails this, but if one did, showing the
            // locale's own string unmodified beats showing nothing.
            return short;
        }
        // Lower-case "h": QLocale treats capital H as "always 24-hour" and then
        // ignores an AM/PM marker, which is the bug KDE's own comment warns
        // about in timeFormatCorrection().
        let result = match[1].toLowerCase() + match[2] + match[3];
        // Keep the country's AM/PM if it has one. No "ap" in the locale's
        // pattern means the country writes 24-hour time, and we leave it alone.
        if (short.toLowerCase().indexOf("ap") !== -1) {
            result += " AP";
        }
        return result;
    }

    // --- size ----------------------------------------------------------------
    // Exactly as wide as the words plus the padding, and no wider. The panel
    // asks a widget how big it wants to be through these three.
    implicitWidth: labels.implicitWidth + compact.horizontalPadding * 2
    implicitHeight: labels.implicitHeight
    Layout.minimumWidth: implicitWidth
    Layout.preferredWidth: implicitWidth
    Layout.maximumWidth: implicitWidth

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton

    // `wasExpanded` handles the awkward case where clicking the widget while the
    // popup is open first closes the popup (because it lost focus) and then
    // delivers the click, which would re-open it. Remembering the state at press
    // time makes the click do what the user meant. Same trick, same reason, as
    // plasma-workspace/applets/digital-clock/DigitalClock.qml.
    property bool wasExpanded: false
    onPressed: compact.wasExpanded = compact.appletExpanded
    onClicked: compact.toggleRequested(compact.wasExpanded)

    Accessible.role: Accessible.Button
    Accessible.name: i18n("Clock and notifications")
    Accessible.description: compact.dateText + " " + compact.timeText
    Accessible.onPressAction: compact.toggleRequested(compact.appletExpanded)

    // The hover wash from the design: white at 8%, 6px corners. This is a tint
    // painted ON TOP of the bar, not see-through-ness — the bar itself stays
    // solid. (See docs/plasma-style.md, "Glass removed".)
    Rectangle {
        anchors.fill: parent
        radius: compact.hoverRadius
        visible: compact.containsMouse
        color: Qt.rgba(Kirigami.Theme.textColor.r,
                       Kirigami.Theme.textColor.g,
                       Kirigami.Theme.textColor.b,
                       0.08)
    }

    RowLayout {
        id: labels
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Label {
            text: compact.dateText
            color: Kirigami.Theme.disabledTextColor
            font.weight: Font.Normal
            textFormat: Text.PlainText
        }

        PlasmaComponents3.Label {
            text: compact.timeText
            color: Kirigami.Theme.textColor
            font.weight: Font.Medium
            textFormat: Text.PlainText
        }
    }
}
