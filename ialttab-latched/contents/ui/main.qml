/*
 * iAltTab Latched Search - KWin Effect
 * SPDX-License-Identifier: MIT
 *
 * Why this exists:
 * - KWin TabBox switchers are modifier-hold switchers. Releasing the shortcut
 *   commits the current selection.
 * - This is a KWin Effect instead, so F19/CapsLock can toggle it open and it
 *   stays open until Enter, Escape, click, or a second shortcut press.
 *
 * Design goals:
 * - No shelling out, no rofi/kdotool startup.
 * - One-shot launcher: tap F19, type, Enter.
 * - MRU-ish ordering maintained inside KWin via Workspace.windowActivated.
 * - Shows class/app-id where KWin exposes it: resourceClass / desktopFileName.
 */

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kwin

SceneEffect {
    id: effect

    // Default shortcut. You can change this in System Settings -> Shortcuts -> KWin.
    readonly property string defaultShortcut: "F19"

    readonly property int maxVisibleRows: 14
    readonly property int rowHeight: Math.round(Kirigami.Units.gridUnit * 2.55)
    readonly property int searchHeight: Math.round(Kirigami.Units.gridUnit * 2.35)
    readonly property int chrome: Kirigami.Units.largeSpacing * 2

    property string query: ""
    property int selectedIndex: 0
    property var mruWindows: []
    property var shownWindows: []

    // SceneEffect creates one delegate per physical/logical screen.
    // Keep the switcher visually active on only the screen that was active
    // at the moment the shortcut was pressed; other delegates stay hidden
    // so KWin does not repaint the inactive screens.
    property string targetScreenKey: ""


    function safeString(value) {
        if (value === undefined || value === null) {
            return "";
        }
        return String(value);
    }

    function safeLower(value) {
        return safeString(value).toLowerCase();
    }

    function screenKey(output) {
        if (!output) {
            return "";
        }

        try {
            const g = output.geometry;
            return safeString(output.name) + "|" + safeString(g.x) + "," + safeString(g.y) + "," + safeString(g.width) + "x" + safeString(g.height);
        } catch (e) {
            return safeString(output.name);
        }
    }

    function chooseTargetScreen() {
        let output = null;

        // Prefer KWin's active screen. This follows the currently focused window
        // and is what users usually expect from a keyboard-launched switcher.
        try {
            output = Workspace.activeScreen;
        } catch (e1) {
            output = null;
        }

        // Fallback: use the screen under the cursor.
        if (!output) {
            try {
                output = Workspace.screenAt(Workspace.cursorPos);
            } catch (e2) {
                output = null;
            }
        }

        targetScreenKey = screenKey(output);
    }

    function isTargetScreen(output) {
        if (targetScreenKey.length === 0) {
            return true;
        }
        return screenKey(output) === targetScreenKey;
    }

    function windowKey(w) {
        if (!w) {
            return "";
        }
        const id = safeString(w.internalId);
        if (id.length > 0 && id !== "undefined" && id !== "null") {
            return id;
        }
        return safeString(w.resourceClass) + "|" + safeString(w.caption) + "|" + safeString(w.pid);
    }

    function sameWindow(a, b) {
        if (!a || !b) {
            return false;
        }
        if (a === b) {
            return true;
        }
        const ak = windowKey(a);
        const bk = windowKey(b);
        return ak.length > 0 && ak === bk;
    }

    function isUsableWindow(w) {
        if (!w) {
            return false;
        }

        try {
            if (w.deleted || !w.managed || w.skipSwitcher || w.desktopWindow || w.dock || w.splash || w.tooltip || w.notification || w.criticalNotification || w.onScreenDisplay || w.inputMethod) {
                return false;
            }

            // Include normal app windows and real dialogs. Exclude popup/menu/tool windows.
            if (!(w.normalWindow || w.dialog)) {
                return false;
            }

            if (safeString(w.caption).length === 0 && safeString(w.resourceClass).length === 0 && safeString(w.desktopFileName).length === 0) {
                return false;
            }
        } catch (e) {
            return false;
        }

        return true;
    }

    function containsWindow(list, w) {
        for (let i = 0; i < list.length; ++i) {
            if (sameWindow(list[i], w)) {
                return true;
            }
        }
        return false;
    }

    function removeWindowFrom(list, w) {
        const out = [];
        for (let i = 0; i < list.length; ++i) {
            if (!sameWindow(list[i], w) && isUsableWindow(list[i])) {
                out.push(list[i]);
            }
        }
        return out;
    }

    function touchWindow(w) {
        if (!isUsableWindow(w)) {
            return;
        }
        const out = removeWindowFrom(mruWindows, w);
        out.unshift(w);
        mruWindows = out;
        if (visible) {
            rebuildShownWindows(false);
        }
    }

    function seedFromStackingOrder() {
        let out = [];

        // Keep what we already know in true MRU order.
        for (let i = 0; i < mruWindows.length; ++i) {
            if (isUsableWindow(mruWindows[i]) && !containsWindow(out, mruWindows[i])) {
                out.push(mruWindows[i]);
            }
        }

        // Add anything that existed before the effect was enabled. Stacking order is
        // not MRU, but reversed stacking order is a good cold-start fallback.
        let stack = [];
        try {
            stack = Workspace.stackingOrder || [];
        } catch (e) {
            stack = [];
        }
        for (let j = stack.length - 1; j >= 0; --j) {
            const w = stack[j];
            if (isUsableWindow(w) && !containsWindow(out, w)) {
                out.push(w);
            }
        }

        mruWindows = out;
    }

    function searchableText(w) {
        return safeLower(w.resourceClass + " " + w.resourceName + " " + w.desktopFileName + " " + w.caption);
    }

    function windowMatches(w) {
        const q = safeLower(query).trim();
        if (q.length === 0) {
            return true;
        }

        const haystack = searchableText(w);
        const words = q.split(/\s+/);
        for (let i = 0; i < words.length; ++i) {
            if (words[i].length > 0 && haystack.indexOf(words[i]) === -1) {
                return false;
            }
        }
        return true;
    }

    function rebuildShownWindows(resetSelection) {
        seedFromStackingOrder();

        const out = [];
        for (let i = 0; i < mruWindows.length; ++i) {
            const w = mruWindows[i];
            if (isUsableWindow(w) && windowMatches(w)) {
                out.push(w);
            }
        }
        shownWindows = out;

        if (shownWindows.length === 0) {
            selectedIndex = 0;
            return;
        }

        if (resetSelection) {
            // Empty-query startup selects the previous window, matching Alt-Tab.
            // Search-query startup selects the first match.
            selectedIndex = query.trim().length === 0 && shownWindows.length > 1 ? 1 : 0;
            return;
        }

        if (selectedIndex < 0) {
            selectedIndex = 0;
        }
        if (selectedIndex >= shownWindows.length) {
            selectedIndex = shownWindows.length - 1;
        }
    }

    function openPicker() {
        query = "";
        chooseTargetScreen();
        rebuildShownWindows(true);
        visible = true;
    }

    function closePicker() {
        visible = false;
        query = "";
        targetScreenKey = "";
    }

    function togglePicker() {
        if (visible) {
            closePicker();
        } else {
            openPicker();
        }
    }

    function moveSelection(delta) {
        if (shownWindows.length <= 0) {
            selectedIndex = 0;
            return;
        }
        selectedIndex = (selectedIndex + delta + shownWindows.length) % shownWindows.length;
    }

    function page(delta) {
        const n = Math.min(5, Math.max(1, shownWindows.length));
        for (let i = 0; i < n; ++i) {
            moveSelection(delta);
        }
    }

    function appendTypedText(text) {
        if (!text || text.length !== 1) {
            return false;
        }
        if (text < " " || text === "\u007f") {
            return false;
        }
        if (query.length === 0 && text.trim().length === 0) {
            return false;
        }
        query += text;
        return true;
    }

    function selectedWindow() {
        if (selectedIndex < 0 || selectedIndex >= shownWindows.length) {
            return null;
        }
        return shownWindows[selectedIndex];
    }

    function activateSelected() {
        const w = selectedWindow();
        if (!isUsableWindow(w)) {
            closePicker();
            return;
        }

        try {
            if (w.minimized) {
                w.minimized = false;
            }
        } catch (e1) {}

        try {
            Workspace.raiseWindow(w);
        } catch (e2) {}

        try {
            Workspace.activeWindow = w;
        } catch (e3) {}

        touchWindow(w);
        closePicker();
    }

    function closeSelectedWindow() {
        const w = selectedWindow();
        if (!isUsableWindow(w) || !w.closeable) {
            return;
        }
        try {
            w.closeWindow();
        } catch (e) {}
        mruWindows = removeWindowFrom(mruWindows, w);
        rebuildShownWindows(false);
    }

    onQueryChanged: rebuildShownWindows(true)

    Component.onCompleted: {
        seedFromStackingOrder();
        if (Workspace.activeWindow) {
            touchWindow(Workspace.activeWindow);
        }
    }

    Connections {
        target: Workspace

        function onWindowActivated(window) {
            touchWindow(window);
        }

        function onWindowAdded(window) {
            if (isUsableWindow(window) && !containsWindow(mruWindows, window)) {
                mruWindows.push(window);
                if (effect.visible) {
                    rebuildShownWindows(false);
                }
            }
        }

        function onWindowRemoved(window) {
            mruWindows = removeWindowFrom(mruWindows, window);
            if (effect.visible) {
                rebuildShownWindows(false);
            }
        }
    }

    ShortcutHandler {
        name: "Toggle iAltTab Latched Search"
        text: "Toggle iAltTab Latched Search"
        sequence: effect.defaultShortcut
        onActivated: effect.togglePicker()
    }

    delegate: Item {
        id: screenRoot
        readonly property bool targetScreen: effect.isTargetScreen(SceneView.screen)

        // Hide non-target delegates entirely so KWin does not composite or
        // clear those screens. Keeps inactive monitors untouched and avoids
        // the brief blackout when the effect activates.
        visible: targetScreen
        focus: targetScreen

        readonly property int rowsShown: Math.max(1, Math.min(effect.shownWindows.length, effect.maxVisibleRows))
        readonly property int panelWidth: Math.round(Math.min(Math.max(Kirigami.Units.gridUnit * 48, width * 0.42), width * 0.82))
        readonly property int panelHeight: effect.chrome + effect.searchHeight + Kirigami.Units.smallSpacing + rowsShown * effect.rowHeight

        Component.onCompleted: {
            if (targetScreen) {
                forceActiveFocus();
            }
        }

        Connections {
            target: effect
            function onVisibleChanged() {
                if (effect.visible && screenRoot.targetScreen) {
                    screenRoot.forceActiveFocus();
                    listView.positionViewAtIndex(effect.selectedIndex, ListView.Contain);
                }
            }
            function onSelectedIndexChanged() {
                listView.positionViewAtIndex(effect.selectedIndex, ListView.Contain);
            }
            function onShownWindowsChanged() {
                if (screenRoot.targetScreen) {
                    listView.positionViewAtIndex(effect.selectedIndex, ListView.Contain);
                }
            }
            function onTargetScreenKeyChanged() {
                if (effect.visible && screenRoot.targetScreen) {
                    screenRoot.forceActiveFocus();
                    listView.positionViewAtIndex(effect.selectedIndex, ListView.Contain);
                }
            }
        }

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: event => {
            if (!screenRoot.targetScreen) {
                event.accepted = false;
                return;
            }

            if (event.key === Qt.Key_Escape) {
                effect.closePicker();
                event.accepted = true;
                return;
            }

            if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_U || event.key === Qt.Key_L)) {
                effect.query = "";
                event.accepted = true;
                return;
            }

            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_W) {
                effect.closeSelectedWindow();
                event.accepted = true;
                return;
            }

            if (event.key === Qt.Key_Backspace) {
                if (effect.query.length > 0) {
                    effect.query = effect.query.slice(0, -1);
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
                return;
            }

            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                effect.activateSelected();
                event.accepted = true;
                return;
            }

            if (event.key === Qt.Key_Down || event.key === Qt.Key_Right || (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier))) {
                effect.moveSelection(1);
                event.accepted = true;
                return;
            }

            if (event.key === Qt.Key_Up || event.key === Qt.Key_Left || event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                effect.moveSelection(-1);
                event.accepted = true;
                return;
            }

            if (event.key === Qt.Key_PageDown) {
                effect.page(1);
                event.accepted = true;
                return;
            }

            if (event.key === Qt.Key_PageUp) {
                effect.page(-1);
                event.accepted = true;
                return;
            }

            if (event.key === Qt.Key_Home) {
                effect.selectedIndex = 0;
                event.accepted = true;
                return;
            }

            if (event.key === Qt.Key_End) {
                effect.selectedIndex = Math.max(0, effect.shownWindows.length - 1);
                event.accepted = true;
                return;
            }

            // Number-key quick pick: 1..9 always activates the Nth visible entry.
            if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9
                    && (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier | Qt.ShiftModifier)) === 0) {
                const idx = event.key - Qt.Key_1;
                if (idx < effect.shownWindows.length) {
                    effect.selectedIndex = idx;
                    effect.activateSelected();
                }
                event.accepted = true;
                return;
            }

            // Keep Ctrl/Alt/Meta chords available to global shortcuts.
            if ((event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) === 0 && effect.appendTypedText(event.text)) {
                event.accepted = true;
                return;
            }

            event.accepted = false;
        }

        Rectangle {
            id: panel
            visible: screenRoot.targetScreen
            width: screenRoot.panelWidth
            height: screenRoot.panelHeight
            x: Math.round((screenRoot.width - width) / 2)
            y: Math.round(Math.max(Kirigami.Units.gridUnit * 2, screenRoot.height * 0.16))
            radius: Math.round(Kirigami.Units.gridUnit * 0.7)
            color: Kirigami.Theme.backgroundColor
            border.width: 1
            border.color: Kirigami.Theme.disabledTextColor
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: effect.searchHeight
                    radius: Math.round(Kirigami.Units.smallSpacing * 1.25)
                    color: Kirigami.Theme.backgroundColor
                    border.width: 1
                    border.color: Kirigami.Theme.disabledTextColor

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                        anchors.rightMargin: Kirigami.Units.smallSpacing * 2
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: "edit-find"
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        }

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: effect.query.length > 0 ? effect.query : "type to filter windows"
                            color: effect.query.length > 0 ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                        }

                        PlasmaComponents3.Label {
                            text: effect.shownWindows.length + "/" + effect.mruWindows.length
                            color: Kirigami.Theme.disabledTextColor
                            textFormat: Text.PlainText
                        }
                    }
                }

                ListView {
                    id: listView
                    Layout.fillWidth: true
                    Layout.preferredHeight: screenRoot.rowsShown * effect.rowHeight
                    clip: true
                    reuseItems: true
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 0
                    highlightResizeDuration: 0
                    currentIndex: effect.selectedIndex
                    model: effect.shownWindows.length

                    delegate: Item {
                        id: rowItem
                        readonly property var win: effect.shownWindows[index]
                        readonly property bool current: index === effect.selectedIndex
                        readonly property string classText: effect.safeString(win ? (win.resourceClass || win.desktopFileName || win.resourceName) : "")
                        readonly property string titleText: effect.safeString(win ? win.caption : "")
                        readonly property bool isMinimized: win ? win.minimized === true : false
                        readonly property bool canClose: win ? win.closeable === true : false

                        width: listView.width
                        height: effect.rowHeight
                        opacity: isMinimized ? 0.62 : 1.0

                        Rectangle {
                            anchors.fill: parent
                            radius: Math.round(Kirigami.Units.smallSpacing * 1.25)
                            color: Kirigami.Theme.highlightColor
                            opacity: rowItem.current ? 0.28 : 0
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                            anchors.rightMargin: Kirigami.Units.smallSpacing * 2
                            spacing: Kirigami.Units.smallSpacing * 1.5

                            Kirigami.Icon {
                                source: rowItem.win ? rowItem.win.icon : "window"
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    text: rowItem.titleText.length > 0 ? rowItem.titleText : rowItem.classText
                                    textFormat: Text.PlainText
                                    elide: Text.ElideMiddle
                                    maximumLineCount: 1
                                    font.weight: rowItem.current ? Font.Bold : Font.Normal
                                }

                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    visible: rowItem.classText.length > 0 || rowItem.isMinimized
                                    text: rowItem.classText + (rowItem.isMinimized ? (rowItem.classText.length > 0 ? "  -  minimized" : "minimized") : "")
                                    color: Kirigami.Theme.disabledTextColor
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.72)
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onClicked: mouse => {
                                effect.selectedIndex = index;
                                if (mouse.button === Qt.MiddleButton) {
                                    effect.closeSelectedWindow();
                                } else {
                                    effect.activateSelected();
                                }
                            }
                        }
                    }

                    Kirigami.PlaceholderMessage {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - Kirigami.Units.largeSpacing * 2, Kirigami.Units.gridUnit * 28)
                        visible: effect.shownWindows.length === 0
                        icon.source: "edit-none"
                        text: "No matching windows"
                    }
                }
            }
        }
    }
}
