/*
 *  Copyright 2012 Marco Martin <mart@kde.org>
 *  Copyright 2014 David Edmundson <davidedmundson@kde.org>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  2.010-1301, USA.
 */

import QtQuick 2.0

import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 2.0 as PlasmaComponents
import org.kde.kwindowsystem 1.0
import org.kde.plasma.activityswitcher 1.0 as ActivitySwitcher
import org.kde.plasma.shell 2.0 as Shell
import "../activitymanager"
import "../explorer"


Item {
    id: root

    property Item containment
    property Item wallpaper

    property QtObject widgetExplorer

    Connections {
        target: ActivitySwitcher.Backend
        onShouldShowSwitcherChanged: {
            if (ActivitySwitcher.Backend.shouldShowSwitcher) {
                if (sidePanelStack.state != "activityManager") {
                    root.toggleActivityManager();
                }

            } else {
                if (sidePanelStack.state == "activityManager") {
                    root.toggleActivityManager();
                }

            }
        }
    }

    function toggleWidgetExplorer(containment) {
//         console.log("Widget Explorer toggled");

        if (sidePanelStack.state == "widgetExplorer") {
            sidePanelStack.state = "closed";
        } else {
            sidePanelStack.state = "widgetExplorer";
            sidePanelStack.setSource(Qt.resolvedUrl("../explorer/WidgetExplorer.qml"), {"containment": containment})
        }
    }

    // Qt has a bug where invoking a global shortcut steal focus from the
    // current window, which makes the activity switcher hide itself and
    // popup again when the user presses meta+q (instead of just hiding).
    // This 'timestamp' forbids the switcher to be toggled consecutively.
    //
    // The relevant patch to Qt is here:
    //     https://codereview.qt-project.org/#/c/143658/
    property int lastToggleActivityManagerTimestamp: 0

    function toggleActivityManager() {
        var currentTimestamp = new Date().getTime() / 1000;

        if (currentTimestamp - lastToggleActivityManagerTimestamp > 1) {
            if (sidePanelStack.state == "activityManager") {
                sidePanelStack.state = "closed";
            } else {
                sidePanelStack.state = "activityManager";
                sidePanelStack.setSource(Qt.resolvedUrl("../activitymanager/ActivityManager.qml"))
            }

            lastToggleActivityManagerTimestamp = currentTimestamp;
        }
    }

    KWindowSystem {
        id: kwindowsystem
    }

    Timer {
        id: pendingUninstallTimer
        // keeps track of the applets the user wants to uninstall
        property var applets: []

        interval: 60000 // one minute
        onTriggered: {
            for (var i = 0, length = applets.length; i < length; ++i) {
                widgetExplorer.uninstall(applets[i])
            }
            applets = []

            if (sidePanelStack.state !== "widgetExplorer" && widgetExplorer) {
                widgetExplorer.destroy()
                widgetExplorer = null
            }
        }
    }

    PlasmaCore.Dialog {
        id: sidePanel
        location: PlasmaCore.Types.LeftEdge
        type: PlasmaCore.Dialog.Dock
        flags: Qt.WindowStaysOnTopHint

        hideOnWindowDeactivate: true

        /*
        If there is no setGeometry call on QWindow the XCB backend will not pass our requested position to kwin
        as our window position tends to be 0, setX,setY no-ops and means we never set a position as far as QWindow is concerned
        by setting it to something silly and setting it back before we show the window we avoid that bug.
        */
        x: -10

        onVisibleChanged: {
            if (!visible) {
                sidePanelStack.state = "closed";
                ActivitySwitcher.Backend.shouldShowSwitcher = false;
            } else {
                var rect = containment.availableScreenRect;
                // get the current available screen geometry and subtract the dialog's frame margins
                sidePanelStack.height = containment ? rect.height - sidePanel.margins.top - sidePanel.margins.bottom : 1000;
                sidePanel.x = desktop.x + rect.x;
                sidePanel.y = desktop.y + rect.y;
            }

            lastToggleActivityManagerTimestamp = new Date().getTime() / 1000;
        }

        mainItem: Loader {
            id: sidePanelStack
            asynchronous: true
            height: 1000 //start with some arbitrary height, will be changed from onVisibleChanged
            width: item ? item.width: 0
            state: "closed"

            onLoaded: {
                if (sidePanelStack.item) {
                    item.closed.connect(function(){sidePanelStack.state = "closed";});

                    if (sidePanelStack.state == "activityManager") {
                        sidePanelStack.item.showSwitcherOnly =
                            ActivitySwitcher.Backend.shouldShowSwitcher
                        sidePanel.hideOnWindowDeactivate = Qt.binding(function() {
                            return !ActivitySwitcher.Backend.shouldShowSwitcher
                                && !sidePanelStack.item.showingDialog;
                        })
                        sidePanelStack.item.forceActiveFocus();
                    } else if (sidePanelStack.state == "widgetExplorer"){
                        sidePanel.hideOnWindowDeactivate = Qt.binding(function() { return sidePanelStack.item && !sidePanelStack.item.preventWindowHide; })
                        sidePanel.opacity = Qt.binding(function() { return sidePanelStack.item ? sidePanelStack.item.opacity : 1 })
                        sidePanel.outputOnly = Qt.binding(function() { return sidePanelStack.item && sidePanelStack.item.outputOnly })
                    } else {
                        sidePanel.hideOnWindowDeactivate = true;
                    }
                }
                sidePanel.visible = true;
                kwindowsystem.forceActivateWindow(sidePanel)
            }
            onStateChanged: {
                if (sidePanelStack.state == "closed") {
                    sidePanel.visible = false;
                    sidePanelStack.source = ""; //unload all elements
                }
            }
        }
    }

    Connections {
        target: containment
        onAvailableScreenRectChanged: {
            var rect = containment.availableScreenRect;
            sidePanel.requestActivate();
            // get the current available screen geometry and subtract the dialog's frame margins
            sidePanelStack.height = containment ? rect.height - sidePanel.margins.top - sidePanel.margins.bottom : 1000;
            sidePanel.x = desktop.x + rect.x;
            sidePanel.y = desktop.y + rect.y;
        }
    }

    onContainmentChanged: {
        //containment.parent = root;

        internal.newContainment = containment;

        if (containment != null) {
            containment.visible = true;
        }
        if (containment != null) {
            if (internal.oldContainment != null && internal.oldContainment != containment) {
                if (internal.newContainment != null) {
                    switchAnim.running = true;
                }
            } else {
                containment.anchors.left = root.left;
                containment.anchors.top = root.top;
                containment.anchors.right = root.right;
                containment.anchors.bottom = root.bottom;
                internal.oldContainment = containment;
            }
        }
    }

    onWallpaperChanged: {
        if (!internal.oldWallpaper) {
            internal.oldWallpaper = wallpaper;
        }
    }

    //some properties that shouldn't be accessible from elsewhere
    QtObject {
        id: internal;

        property Item oldContainment: null;
        property Item newContainment: null;
        property Item oldWallpaper: null;
    }

    SequentialAnimation {
        id: switchAnim
        ScriptAction {
            script: {
                if (containment) {
                    containment.anchors.left = undefined;
                    containment.anchors.top = undefined;
                    containment.anchors.right = undefined;
                    containment.anchors.bottom = undefined;
                }
                internal.oldContainment.anchors.left = undefined;
                internal.oldContainment.anchors.top = undefined;
                internal.oldContainment.anchors.right = undefined;
                internal.oldContainment.anchors.bottom = undefined;

                if (containment) {
                    internal.oldContainment.z = 0;
                    internal.oldContainment.x = 0;
                    containment.z = 1;
                    containment.x = root.width;
                }
            }
        }
        ParallelAnimation {
            NumberAnimation {
                target: internal.oldContainment
                properties: "x"
                to: internal.newContainment != null ? -root.width : 0
                duration: 400
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                target: internal.newContainment
                properties: "x"
                to: 0
                duration: units.longDuration
                easing.type: Easing.InOutQuad
            }
        }
        ScriptAction {
            script: {
                if (containment) {
                    containment.anchors.left = root.left;
                    containment.anchors.top = root.top;
                    containment.anchors.right = root.right;
                    containment.anchors.bottom = root.bottom;
                    internal.oldContainment.visible = false;
                    internal.oldWallpaper.opacity = 1;
                    internal.oldContainment = containment;
                    internal.oldWallpaper = wallpaper;
                }
            }
        }
    }


    Component.onCompleted: {
        //configure the view behavior
        desktop.windowType = Shell.Desktop.Desktop;
    }
}
