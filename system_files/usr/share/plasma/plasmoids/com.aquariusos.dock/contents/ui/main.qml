/*
    SPDX-FileCopyrightText: 2012-2016 Eike Hein <hein@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.core as PlasmaCore
import org.kde.ksvg as KSvg
import org.kde.plasma.private.mpris as Mpris
import org.kde.kirigami as Kirigami

import org.kde.plasma.workspace.trianglemousefilter

import org.kde.taskmanager as TaskManager
import "code/LayoutMetrics.js" as LayoutMetrics
import "code/TaskTools.js" as TaskTools
import org.kde.plasma.workspace.dbus as DBus

PlasmoidItem {
    id: tasks

    // For making a bottom to top layout since qml flow can't do that.
    // We just hang the task manager upside down to achieve that.
    // This mirrors the tasks and group dialog as well, so we un-rotate them
    // to fix that (see Task.qml and GroupDialog.qml).
    rotation: Plasmoid.configuration.reverseMode && Plasmoid.formFactor === PlasmaCore.Types.Vertical ? 180 : 0

    readonly property bool shouldShrinkToZero: tasksModel.count === 0
    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool iconsOnly: Plasmoid.pluginName === "com.aquariusos.dock"

    property Task toolTipOpenedByClick
    property Task toolTipAreaItem

    readonly property Component contextMenuComponent: Qt.createComponent("ContextMenu.qml")
    readonly property Component pulseAudioComponent: Qt.createComponent("PulseAudio.qml")

    property alias taskList: taskList

    preferredRepresentation: fullRepresentation

    Plasmoid.constraintHints: Plasmoid.CanFillArea

    Plasmoid.onUserConfiguringChanged: {
        if (Plasmoid.userConfiguring && groupDialog !== null) {
            groupDialog.visible = false;
        }
    }

    Layout.fillWidth: vertical ? true : Plasmoid.configuration.fill
    Layout.fillHeight: !vertical ? true : Plasmoid.configuration.fill
    Layout.minimumWidth: {
        if (shouldShrinkToZero) {
            return Kirigami.Units.gridUnit; // For edit mode
        }
        return vertical ? 0 : LayoutMetrics.preferredMinWidth();
    }
    Layout.minimumHeight: {
        if (shouldShrinkToZero) {
            return Kirigami.Units.gridUnit; // For edit mode
        }
        return !vertical ? 0 : LayoutMetrics.preferredMinHeight();
    }

//BEGIN TODO: this is not precise enough: launchers are smaller than full tasks
    // AQUARIUS DEVIATION — the two `aqAddTile` terms below.
    //
    // The dock panel is set to "fit" length, which means the panel is exactly as
    // wide as this widget asks to be. The "add an app" tile is drawn after the
    // row of apps, so the widget has to ask for one tile more than the apps need
    // — otherwise the panel ends at the last app and the + tile hangs off the
    // end of the dock, outside its background.
    //
    // Everything else in these two blocks is upstream, untouched.
    Layout.preferredWidth: {
        if (shouldShrinkToZero) {
            return 0.01;
        }
        if (vertical) {
            return Kirigami.Units.gridUnit * 10;
        }
        return taskList.Layout.maximumWidth + (aqAddTile.visible ? aqAddTile.width : 0)
    }
    Layout.preferredHeight: {
        if (shouldShrinkToZero) {
            return 0.01;
        }
        if (vertical) {
            return taskList.Layout.maximumHeight + (aqAddTile.visible ? aqAddTile.height : 0)
        }
        return Kirigami.Units.gridUnit * 2;
    }
//END TODO

    property Item dragSource

    signal requestLayout

    onDragSourceChanged: {
        if (dragSource === null) {
            tasksModel.syncLaunchers();
        }
    }

    function windowsHovered(winIds: var, hovered: bool): DBus.DBusPendingReply {
        if (!Plasmoid.configuration.highlightWindows) {
            return;
        }
        return DBus.SessionBus.asyncCall({service: "org.kde.KWin.HighlightWindow", path: "/org/kde/KWin/HighlightWindow", iface: "org.kde.KWin.HighlightWindow", member: "highlightWindows", arguments: [hovered ? winIds : []], signature: "(as)"});
    }

    function cancelHighlightWindows(): DBus.DBusPendingReply {
        return DBus.SessionBus.asyncCall({service: "org.kde.KWin.HighlightWindow", path: "/org/kde/KWin/HighlightWindow", iface: "org.kde.KWin.HighlightWindow", member: "highlightWindows", arguments: [[]], signature: "(as)"});
    }

    function activateWindowView(winIds: var): DBus.DBusPendingReply {
        if (!effectWatcher.registered) {
            return;
        }
        cancelHighlightWindows();
        return DBus.SessionBus.asyncCall({service: "org.kde.KWin.Effect.WindowView1", path: "/org/kde/KWin/Effect/WindowView1", iface: "org.kde.KWin.Effect.WindowView1", member: "activate", arguments: [winIds.map(s => String(s))], signature: "(as)"});
    }

    function publishIconGeometries(taskItems: /*list<Item>*/var): void {
        if (TaskTools.taskManagerInstanceCount >= 2) {
            return;
        }
        for (let i = 0; i < taskItems.length - 1; ++i) {
            const task = taskItems[i];

            if (!task.model.IsLauncher && !task.model.IsStartup) {
                tasksModel.requestPublishDelegateGeometry(tasksModel.makeModelIndex(task.index),
                    backend.globalRect(task), task);
            }
        }
    }

    readonly property TaskManager.TasksModel tasksModel: TaskManager.TasksModel {
        id: tasksModel

        readonly property int logicalLauncherCount: {
            if (Plasmoid.configuration.separateLaunchers) {
                return launcherCount;
            }

            let startupsWithLaunchers = 0;

            for (let i = 0; i < taskRepeater.count; ++i) {
                const item = taskRepeater.itemAt(i) as Task;

                // During destruction required properties such as item.model can go null for a while,
                // so in paths that can trigger on those moments, they need to be guarded
                if (item?.model?.IsStartup && item.model.HasLauncher) {
                    ++startupsWithLaunchers;
                }
            }

            return launcherCount + startupsWithLaunchers;
        }

        screenGeometry: Plasmoid.containment.screenGeometry
        activity: activityInfo.currentActivity

        filterByCurrentVirtualDesktop: Plasmoid.configuration.showOnlyCurrentDesktop
        filterByScreen: Plasmoid.configuration.showOnlyCurrentScreen
        filterByActivity: Plasmoid.configuration.showOnlyCurrentActivity
        filterNotMinimized: Plasmoid.configuration.showOnlyMinimized

        hideActivatedLaunchers: tasks.iconsOnly || Plasmoid.configuration.hideLauncherOnStart
        sortMode: sortModeEnumValue(Plasmoid.configuration.sortingStrategy)
        launchInPlace: tasks.iconsOnly && Plasmoid.configuration.sortingStrategy === 1
        separateLaunchers: {
            if (!tasks.iconsOnly && !Plasmoid.configuration.separateLaunchers
                && Plasmoid.configuration.sortingStrategy === 1) {
                return false;
            }

            return true;
        }

        groupMode: groupModeEnumValue(Plasmoid.configuration.groupingStrategy)
        groupInline: !Plasmoid.configuration.groupPopups && !tasks.iconsOnly
        groupingWindowTasksThreshold: (Plasmoid.configuration.onlyGroupWhenFull && !tasks.iconsOnly
            ? LayoutMetrics.optimumCapacity(tasks.width, tasks.height) + 1 : -1)

        onLauncherListChanged: {
            Plasmoid.configuration.launchers = launcherList;
        }

        onGroupingAppIdBlacklistChanged: {
            Plasmoid.configuration.groupingAppIdBlacklist = groupingAppIdBlacklist;
        }

        onGroupingLauncherUrlBlacklistChanged: {
            Plasmoid.configuration.groupingLauncherUrlBlacklist = groupingLauncherUrlBlacklist;
        }

        function sortModeEnumValue(index: int): /*TaskManager.TasksModel.SortMode*/ int {
            switch (index) {
            case 0:
                return TaskManager.TasksModel.SortDisabled;
            case 1:
                return TaskManager.TasksModel.SortManual;
            case 2:
                return TaskManager.TasksModel.SortAlpha;
            case 3:
                return TaskManager.TasksModel.SortVirtualDesktop;
            case 4:
                return TaskManager.TasksModel.SortActivity;
            // 5 is SortLastActivated, skipped
            case 6:
                return TaskManager.TasksModel.SortWindowPositionHorizontal;
            default:
                return TaskManager.TasksModel.SortDisabled;
            }
        }

        function groupModeEnumValue(index: int): /*TaskManager.TasksModel.GroupMode*/ int {
            switch (index) {
            case 0:
                return TaskManager.TasksModel.GroupDisabled;
            case 1:
                return TaskManager.TasksModel.GroupApplications;
            }
        }

        Component.onCompleted: {
            launcherList = Plasmoid.configuration.launchers;
            groupingAppIdBlacklist = Plasmoid.configuration.groupingAppIdBlacklist;
            groupingLauncherUrlBlacklist = Plasmoid.configuration.groupingLauncherUrlBlacklist;

            // Only hook up view only after the above churn is done.
            taskRepeater.model = tasksModel;
        }
    }

    readonly property AquariusBackend backend: AquariusBackend {
        id: backend

        onAddLauncher: url => {
            tasks.addLauncher(url);
        }
    }

    DBus.DBusServiceWatcher {
        id: effectWatcher
        busType: DBus.BusType.Session
        watchedService: "org.kde.KWin.Effect.WindowView1"
    }

    readonly property Component taskInitComponent: Component {
        Timer {
            interval: 200
            running: true

            onTriggered: {
                const task = parent as Task;
                if (task) {
                    tasks.tasksModel.requestPublishDelegateGeometry(task.modelIndex(), tasks.backend.globalRect(task), task);
                }
                destroy();
            }
        }
    }

    Connections {
        target: Plasmoid

        function onLocationChanged(): void {
            if (TaskTools.taskManagerInstanceCount >= 2) {
                return;
            }
            // This is on a timer because the panel may not have
            // settled into position yet when the location prop-
            // erty updates.
            iconGeometryTimer.start();
        }
    }

    Connections {
        target: Plasmoid.containment

        function onScreenGeometryChanged(): void {
            iconGeometryTimer.start();
        }
    }

    Mpris.Mpris2Model {
        id: mpris2Source
    }

    Item {
        anchors.fill: parent

        TaskManager.VirtualDesktopInfo {
            id: virtualDesktopInfo
        }

        TaskManager.ActivityInfo {
            id: activityInfo
            readonly property string nullUuid: "00000000-0000-0000-0000-000000000000"
        }

        Loader {
            id: pulseAudio
            sourceComponent: tasks.pulseAudioComponent
            active: tasks.pulseAudioComponent.status === Component.Ready
        }

        Timer {
            id: iconGeometryTimer

            interval: 500
            repeat: false

            onTriggered: {
                tasks.publishIconGeometries(taskList.children, tasks);
            }
        }

        Binding {
            target: Plasmoid
            property: "status"
            value: (tasksModel.anyTaskDemandsAttention && Plasmoid.configuration.unhideOnAttention
                ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.PassiveStatus)
            restoreMode: Binding.RestoreBinding
        }

        Connections {
            target: Plasmoid.configuration

            function onLaunchersChanged(): void {
                tasksModel.launcherList = Plasmoid.configuration.launchers
            }
            function onGroupingAppIdBlacklistChanged(): void {
                tasksModel.groupingAppIdBlacklist = Plasmoid.configuration.groupingAppIdBlacklist;
            }
            function onGroupingLauncherUrlBlacklistChanged(): void {
                tasksModel.groupingLauncherUrlBlacklist = Plasmoid.configuration.groupingLauncherUrlBlacklist;
            }
        }

        Component {
            id: busyIndicator
            PlasmaComponents3.BusyIndicator {}
        }

        // Save drag data
        Item {
            id: dragHelper

            Drag.dragType: Drag.Automatic
            Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
            Drag.onDragFinished: dropAction => {
                tasks.dragSource = null;
            }
        }

        KSvg.FrameSvgItem {
            id: taskFrame

            visible: false

            imagePath: "widgets/tasks"
            prefix: TaskTools.taskPrefix("normal", Plasmoid.location)
        }

        MouseHandler {
            id: mouseHandler

            anchors.fill: parent

            target: taskList

            onUrlsDropped: urls => {
                // If all dropped URLs point to application desktop files, we'll add a launcher for each of them.
                const createLaunchers = urls.every(item => tasks.backend.isApplication(item));

                if (createLaunchers) {
                    urls.forEach(item => addLauncher(item));
                    return;
                }

                if (!hoveredItem) {
                    return;
                }

                // Otherwise we'll just start a new instance of the application with the URLs as argument,
                // as you probably don't expect some of your files to open in the app and others to spawn launchers.
                tasksModel.requestOpenUrls((hoveredItem as Task).modelIndex(), urls);
            }
        }

        ToolTipDelegate {
            id: openWindowToolTipDelegate
            visible: false
        }

        ToolTipDelegate {
            id: pinnedAppToolTipDelegate
            visible: false
        }

        TriangleMouseFilter {
            id: tmf
            filterTimeOut: 300
            active: tasks.toolTipAreaItem && tasks.toolTipAreaItem.toolTipOpen
            blockFirstEnter: false

            edge: {
                switch (Plasmoid.location) {
                case PlasmaCore.Types.BottomEdge:
                    return Qt.TopEdge;
                case PlasmaCore.Types.TopEdge:
                    return Qt.BottomEdge;
                case PlasmaCore.Types.LeftEdge:
                    return Qt.RightEdge;
                case PlasmaCore.Types.RightEdge:
                    return Qt.LeftEdge;
                default:
                    return Qt.TopEdge;
                }
            }

            LayoutMirroring.enabled: tasks.shouldBeMirrored(Plasmoid.configuration.reverseMode, Application.layoutDirection, tasks.vertical)
            anchors {
                left: parent.left
                top: parent.top
            }

            height: taskList.height
            width: taskList.width

            TaskList {
                id: taskList

                LayoutMirroring.enabled: tasks.shouldBeMirrored(Plasmoid.configuration.reverseMode, Application.layoutDirection, tasks.vertical)
                anchors {
                    left: parent.left
                    top: parent.top
                }

                count: tasksModel.count

                readonly property real widthOccupation: taskRepeater.count / columns
                readonly property real heightOccupation: taskRepeater.count / rows

                Layout.maximumWidth: {
                    const totalMaxWidth = children.reduce((accumulator, child) => {
                            if (!isFinite(child.Layout.maximumWidth)) {
                                return accumulator;
                            }
                            return accumulator + child.Layout.maximumWidth
                        }, 0);
                    return Math.round(totalMaxWidth / widthOccupation);
                }
                Layout.maximumHeight: {
                    const totalMaxHeight = children.reduce((accumulator, child) => {
                            if (!isFinite(child.Layout.maximumHeight)) {
                                return accumulator;
                            }
                            return accumulator + child.Layout.maximumHeight
                        }, 0);
                    return Math.round(totalMaxHeight / heightOccupation);
                }
                width: {
                    if (tasks.shouldShrinkToZero) {
                        return 0;
                    }
                    if (tasks.vertical) {
                        return tasks.width * Math.min(1, widthOccupation);
                    } else {
                        return Math.min(tasks.width, Layout.maximumWidth);
                    }
                }
                height: {
                    if (tasks.shouldShrinkToZero) {
                        return 0;
                    }
                    if (tasks.vertical) {
                        return Math.min(tasks.height, Layout.maximumHeight);
                    } else {
                        return tasks.height * Math.min(1, heightOccupation);
                    }
                }

                flow: {
                    if (tasks.vertical) {
                        return Plasmoid.configuration.forceStripes ? Grid.LeftToRight : Grid.TopToBottom
                    }
                    return Plasmoid.configuration.forceStripes ? Grid.TopToBottom : Grid.LeftToRight
                }

                onAnimatingChanged: {
                    if (!animating) {
                        tasks.publishIconGeometries(children, tasks);
                    }
                }

                Repeater {
                    id: taskRepeater

                    delegate: Task {
                        tasksRoot: tasks
                    }
                }
            }
        }

        // AQUARIUS DEVIATION — the "add an app" tile.
        //
        // A dashed outline of a tile, with a + in it, sitting after the last app
        // in the dock. Clicking it opens the full-screen app grid. This is the
        // last element of the V2 dock design that stock Plasma has no option for
        // (branding/design-system/AquariusOS Desktop Shell.html, the last
        // `.dock-ico`, marked `border-style: dashed`, title "Add an app").
        //
        // WHAT THE CLICK DOES, AND WHY THIS WAY
        // .....................................
        // It calls `activateLauncherMenu` on plasmashell over D-Bus. That is
        // Plasma's own published way of saying "open the app launcher": the
        // shell walks its panels, finds the widget that advertises itself as a
        // launcher menu, and opens it.
        //
        // On AquariusOS that widget is the AquariusOS mark in the top bar, which
        // the layout script sets to Application Dashboard — the full-screen grid
        // of every installed app, with a live search box. So this tile opens
        // exactly the surface the design draws, and it opens the SAME one the
        // logo opens, rather than a second copy of it.
        //
        // If Royce ever swaps the top-bar launcher for a different one, this
        // tile follows it automatically, because the shell resolves "the
        // launcher" at click time rather than us naming one here.
        //
        // Other ways to do this were considered and rejected; the list, with the
        // reason each one is worse, is in FORK-NOTES.md and docs/aquarius-dock.md.
        //
        // The tile is not a drop target and is not draggable — it is a button.
        // Dropping an app onto the DOCK still pins it, as it always did; that is
        // handled by MouseHandler above and is untouched.
        PlasmaCore.ToolTipArea {
            id: aqAddTile

            // Line the tile up with the apps, just after the last one — to the
            // right of them on a bottom dock, below them on a side dock.
            anchors {
                left: tasks.vertical ? undefined : tmf.right
                verticalCenter: tasks.vertical ? undefined : tmf.verticalCenter
                top: tasks.vertical ? tmf.bottom : undefined
                horizontalCenter: tasks.vertical ? tmf.horizontalCenter : undefined
            }

            visible: !tasks.shouldShrinkToZero

            // Square, the same size as a task tile: a task tile fills the dock's
            // thickness, so on a bottom dock that is the dock's height.
            readonly property real tileSize: tasks.vertical ? tasks.width : tasks.height

            width: tileSize
            height: tileSize

            // The same 4-in-32 inset the theme's tasks.svg draws into every task
            // tile, so this outline sits on exactly the same line as the
            // highlight behind a hovered app instead of a pixel off it.
            readonly property real inset: Math.round(tileSize * 4 / 32)

            mainText: i18nc("@info:tooltip", "Add an app")
            subText: i18nc("@info:tooltip", "Show all installed applications")

            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: mainText
            Accessible.description: subText
            Keys.onReturnPressed: aqAddTile.activate()
            Keys.onEnterPressed: aqAddTile.activate()
            Keys.onSpacePressed: aqAddTile.activate()

            function activate(): void {
                DBus.SessionBus.asyncCall({
                    service: "org.kde.plasmashell",
                    path: "/PlasmaShell",
                    iface: "org.kde.PlasmaShell",
                    member: "activateLauncherMenu",
                    arguments: [],
                    signature: "()"
                });
            }

            // The same hover lift the app icons get. In the design this tile is
            // an ordinary dock tile and lifts like the rest of them.
            readonly property bool lifted: aqAddTileMouse.containsMouse
                                           && Plasmoid.configuration.taskHoverEffect

            scale: lifted ? 1.08 : 1.0

            Behavior on scale {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.Bezier
                    easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                }
            }

            transform: Translate {
                y: aqAddTile.lifted ? -4 : 0

                Behavior on y {
                    NumberAnimation {
                        duration: 120
                        easing.type: Easing.Bezier
                        easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                    }
                }
            }

            // Rectangle cannot draw a dashed border, so the outline is painted
            // by hand. Everything about it comes from the design: an 11px corner
            // radius, a hairline stroke, and a dash pattern fine enough to read
            // as "not a real tile yet" at dock size.
            Canvas {
                id: aqAddTileOutline

                anchors.fill: parent
                antialiasing: true

                readonly property color strokeColor: Kirigami.Theme.disabledTextColor
                readonly property real radius: Math.round(aqAddTile.tileSize * 11 / 44)

                onStrokeColorChanged: requestPaint()
                onRadiusChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();

                    const inset = aqAddTile.inset;
                    const lineWidth = 1;
                    // Sit the stroke on a half-pixel so a 1px line stays 1px
                    // instead of blurring across two.
                    const x = inset + lineWidth / 2;
                    const y = inset + lineWidth / 2;
                    const w = width - 2 * inset - lineWidth;
                    const h = height - 2 * inset - lineWidth;

                    if (w <= 0 || h <= 0) {
                        return;
                    }

                    ctx.strokeStyle = strokeColor;
                    ctx.lineWidth = lineWidth;
                    ctx.setLineDash([3, 3]);
                    ctx.beginPath();
                    ctx.roundedRect(x, y, w, h, radius, radius);
                    ctx.stroke();
                }
            }

            PlasmaComponents3.Label {
                anchors.centerIn: parent
                text: "+"
                color: Kirigami.Theme.disabledTextColor
                // Sized as a fraction of the tile so it holds its proportions at
                // any dock thickness: the design draws an 18px "+" on a 44px tile.
                font.pixelSize: Math.round(aqAddTile.tileSize * 18 / 44)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            MouseArea {
                id: aqAddTileMouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor

                onClicked: aqAddTile.activate()
            }
        }
    }

    readonly property Component groupDialogComponent: Qt.createComponent("GroupDialog.qml")
    property GroupDialog groupDialog

    readonly property bool supportsLaunchers: true

    function hasLauncher(url: url): bool {
        return tasksModel.launcherPosition(url) !== -1;
    }

    function addLauncher(url: url): void {
        if (Plasmoid.immutability !== PlasmaCore.Types.SystemImmutable) {
            tasksModel.requestAddLauncher(url);
        }
    }

    function removeLauncher(url: url): void {
        if (Plasmoid.immutability !== PlasmaCore.Types.SystemImmutable) {
            tasksModel.requestRemoveLauncher(url);
        }
    }

    // This is called by plasmashell in response to a Meta+number shortcut.
    // TODO: Change type to int
    function activateTaskAtIndex(index: var): void {
        if (typeof index !== "number") {
            return;
        }

        const task = taskRepeater.itemAt(index) as Task;
        if (task) {
            TaskTools.activateTask(task.modelIndex(), task.model, null, task, Plasmoid, this, effectWatcher.registered);
        }
    }

    function createContextMenu(rootTask, modelIndex, args = {}) {
        const initialArgs = Object.assign(args, {
            visualParent: rootTask,
            modelIndex,
            mpris2Source,
            backend,
        });
        return contextMenuComponent.createObject(rootTask, initialArgs);
    }

    function shouldBeMirrored(reverseMode, layoutDirection, vertical): bool {
        // LayoutMirroring is only horizontal
        if (vertical) {
            return layoutDirection === Qt.RightToLeft;
        }

        if (layoutDirection === Qt.LeftToRight) {
            return reverseMode;
        }
        return !reverseMode;
    }

    Component.onCompleted: {
        TaskTools.taskManagerInstanceCount += 1;
        requestLayout.connect(iconGeometryTimer.restart);
    }

    Component.onDestruction: {
        TaskTools.taskManagerInstanceCount -= 1;
    }
}
