import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

KeyboardPanel {
    id: root

    property var controller
    property alias addPathText: addForm.pathText
    property alias addLabelText: addForm.labelText
    property alias addIdText: addForm.idText
    property alias selectedDeviceIds: addForm.selectedDeviceIds
    property alias pendingFolderValue: addForm.pendingFolderValue

    function resetAddForm() {
        addForm.reset();
    }

    function closeTransientPopups() {
        moreDetails.closePopups();
        addForm.closePopups();
    }

    function focusAddPath() {
        addForm.focusPath();
    }

    function focusPanel() {
        keyCatcher.forceActiveFocus();
    }

    function scrollToTop() {
        panelFlick.contentY = 0;
    }

    focusTarget: keyCatcher
    contentWidth: fittedContentWidth(Style.space(380))
    contentHeight: fittedContentHeight(content.implicitHeight + fixedActions.height + shortcutHint.implicitHeight + Style.space(fixedActions.visible ? 24 : 12), Style.space(560))

    PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        blocked: root.controller.addOpen || moreDetails.folderPopupOpen || moreDetails.pendingPopupOpen
        onCloseRequested: {
            if (root.controller.serviceStateDialogOpen) {
                root.controller.close();
            } else if (root.controller.removalConfirmOpen) {
                root.controller.removalConfirmOpen = false;
            } else if (root.controller.settingsMenuOpen) {
                root.controller.closeSettingsMenu();
            } else if (root.controller.forgetConfirmOpen) {
                root.controller.forgetConfirmOpen = false;
                root.controller.forgetFolderId = "";
            } else if (root.controller.addOpen)
                root.controller.closeAddFolder();
            else
                root.controller.close();
        }
        onTabRequested: function (direction) {
            if (root.controller.serviceStateDialogOpen) {
                serviceStateDialog.selectedChoice = serviceStateDialog.selectedChoice === 0 ? 1 : 0;
            } else if (root.controller.removalConfirmOpen) {
                removalDialog.selectedChoice = (removalDialog.selectedChoice + (direction > 0 ? 1 : 2)) % 3;
            } else if (root.controller.settingsMenuOpen) {
                root.controller.moveSettingsSelection(direction);
            } else
                root.controller.switchPanel(direction);
        }
        onMoveRequested: function (dx, dy) {
            if (root.controller.serviceStateDialogOpen && (dx !== 0 || dy !== 0)) {
                serviceStateDialog.selectedChoice = serviceStateDialog.selectedChoice === 0 ? 1 : 0;
            } else if (root.controller.removalConfirmOpen && dy !== 0) {
                removalDialog.selectedChoice = (removalDialog.selectedChoice + (dy > 0 ? 1 : 2)) % 3;
            } else if (root.controller.settingsMenuOpen && dy !== 0) {
                root.controller.moveSettingsSelection(dy);
            } else if (root.controller.forgetConfirmOpen && (dx !== 0 || dy !== 0)) {
                forgetDialog.selectedIndex = forgetDialog.selectedIndex === 0 ? 1 : 0;
            } else if (!root.controller.addOpen && dx !== 0) {
                root.controller.selectFolderOffset(dx);
            }
        }
        onActivateRequested: {
            if (root.controller.serviceStateDialogOpen) {
                serviceStateDialog.choose();
            } else if (root.controller.removalConfirmOpen) {
                removalDialog.choose();
            } else if (root.controller.settingsMenuOpen) {
                root.controller.activateSettingsSelection();
            } else if (root.controller.forgetConfirmOpen) {
                if (forgetDialog.selectedIndex === 0) {
                    root.controller.forgetConfirmOpen = false;
                    root.controller.forgetFolderId = "";
                } else
                    root.controller.confirmForget();
            }
        }
        onTextKey: function (text) {
            var key = text.toLowerCase();
            if (root.controller.serviceStateDialogOpen) {
                if (key === "q")
                    root.controller.close();
                return;
            }
            if (root.controller.removalConfirmOpen) {
                if (key === "q")
                    root.controller.removalConfirmOpen = false;
                return;
            }
            if (root.controller.settingsMenuOpen) {
                if (key === "q")
                    root.controller.closeSettingsMenu();
                return;
            }
            if (root.controller.forgetConfirmOpen)
                return;
            if (key === "r" && root.controller.syncthing) {
                root.controller.syncthing.refresh();
            } else if (key === "w")
                root.controller.openWebUi();
            else if (key === "p")
                root.controller.toggleSyncing();
            else if (key === "s")
                root.controller.openSettingsMenu();
            else if (key === "q")
                root.controller.close();
        }
    }

    Flickable {
        id: panelFlick
        parent: keyCatcher
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: fixedActions.top
        anchors.bottomMargin: Style.space(12)
        anchors.left: parent.left
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        Column {
            id: content
            width: panelFlick.width
            spacing: Style.space(12)

            PanelStatus {
                visible: !root.controller.settingsMenuOpen
                controller: root.controller
                syncthing: root.controller.syncthing
                foreground: root.controller.foreground
                urgent: root.controller.urgent
                warning: root.controller.warning
                success: root.controller.success
                fontFamily: root.controller.fontFamily
            }

            PanelSeparator {
                visible: !root.controller.settingsMenuOpen
                foreground: root.controller.foreground
            }

            Column {
                visible: !root.controller.settingsMenuOpen
                width: parent.width
                spacing: Style.space(8)

                PanelSectionHeader {
                    text: "FOLDERS"
                    foreground: root.controller.foreground
                    fontFamily: root.controller.fontFamily
                }

                AddFolderForm {
                    id: addForm
                    visible: root.controller.addOpen
                    controller: root.controller
                    syncthing: root.controller.syncthing
                    folderPickerRunning: root.controller.folderPickerRunning
                    foreground: root.controller.foreground
                    dim: root.controller.dim
                    urgent: root.controller.urgent
                    warning: root.controller.warning
                    success: root.controller.success
                    fontFamily: root.controller.fontFamily
                }

                FolderOverview {
                    id: folderOverview
                    controller: root.controller
                    syncthing: root.controller.syncthing
                    foreground: root.controller.foreground
                    dim: root.controller.dim
                    urgent: root.controller.urgent
                    success: root.controller.success
                    syncColor: root.controller.syncthingBlue
                    fontFamily: root.controller.fontFamily
                }
            }

            Button {
                visible: !root.controller.settingsMenuOpen
                width: parent.width
                text: root.controller.moreOpen ? "Less" : "More"
                iconText: root.controller.moreOpen ? "\uf077" : "\uf078"
                leftAlign: true
                foreground: root.controller.foreground
                fontFamily: root.controller.fontFamily
                onClicked: root.controller.moreOpen = !root.controller.moreOpen
            }

            MoreDetails {
                id: moreDetails
                visible: !root.controller.settingsMenuOpen && root.controller.moreOpen
                controller: root.controller
                syncthing: root.controller.syncthing
                foreground: root.controller.foreground
                dim: root.controller.dim
                urgent: root.controller.urgent
                success: root.controller.success
                fontFamily: root.controller.fontFamily
            }

            SettingsMenu {
                visible: root.controller.settingsMenuOpen
                width: parent.width
                selectedIndex: root.controller.settingsSelectedIndex
                fontFamily: root.controller.fontFamily
                onHighlightRequested: function (index) {
                    root.controller.settingsSelectedIndex = index;
                }
                onActivated: function (index) {
                    root.controller.settingsSelectedIndex = index;
                    root.controller.activateSettingsSelection();
                }
            }
        }
    }

    Column {
        id: fixedActions
        parent: keyCatcher
        visible: !root.controller.settingsMenuOpen
        height: visible ? implicitHeight : 0
        anchors.right: parent.right
        anchors.bottom: shortcutHint.top
        anchors.bottomMargin: Style.space(12)
        anchors.left: parent.left
        spacing: Style.space(12)

        PanelSeparator {
            foreground: root.controller.foreground
        }

        Row {
            spacing: Style.space(8)

            Button {
                id: refreshButton
                text: root.controller.syncthing && root.controller.syncthing.refreshing ? "Refreshing…" : "Refresh"
                bordered: true
                foreground: root.controller.foreground
                fontFamily: root.controller.fontFamily
                enabled: root.controller.syncthing && !root.controller.syncthing.refreshing && !root.controller.syncthing.folderMutationBusy
                onClicked: root.controller.syncthing.refresh()
            }

            Button {
                text: "Open Web UI"
                bordered: true
                foreground: root.controller.foreground
                fontFamily: root.controller.fontFamily
                enabled: root.controller.syncthing !== null && root.controller.syncthing.online
                onClicked: root.controller.openWebUi()
            }

            Button {
                width: refreshButton.height
                height: refreshButton.height
                iconText: "\uf013"
                iconSize: Style.font.body
                tooltipText: "Settings"
                bordered: true
                foreground: root.controller.foreground
                fontFamily: root.controller.fontFamily
                enabled: root.controller.syncthing !== null
                onClicked: root.controller.openSettingsMenu()
            }
        }
    }

    Text {
        id: shortcutHint
        parent: keyCatcher
        z: root.controller.removalConfirmOpen ? 12 : 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        text: root.controller.settingsMenuOpen ? "MOVE (j/k or Up/Down)  SELECT (Enter)  BACK (q/Esc)" : "[r]efresh  [w]eb UI  [p]ause/continue  [s]ettings"
        color: root.controller.dim
        font.family: root.controller.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 0.8
    }

    ServiceStateDialog {
        id: serviceStateDialog
        parent: keyCatcher
        anchors.fill: parent
        opened: root.controller.serviceStateDialogOpen
        busy: root.controller.syncthing
            ? root.controller.syncthing.serviceStateActionRunning : false
        message: root.controller.syncthing
            ? root.controller.syncthing.serviceStateMessage : ""
        primaryText: root.controller.syncthing
            ? root.controller.syncthing.serviceStatePrimaryLabel : ""
        secondaryText: root.controller.syncthing
            ? root.controller.syncthing.serviceStateSecondaryLabel : ""
        fontFamily: root.controller.fontFamily
        z: 12
        onActionRequested: function (index) {
            root.controller.chooseServiceStateAction(index);
        }
    }

    CompactConfirmDialog {
        id: forgetDialog
        parent: keyCatcher
        anchors.fill: parent
        opened: root.controller.forgetConfirmOpen
        z: 10
        message: {
            var folder = root.controller.selectedFolder();
            return folder ? "Forget " + folder.label + " (" + folder.id + ")?\n\n" + "This removes only its Syncthing configuration. The " + "directory and data files will not be deleted. " + (folder.markerName === ".stfolder" ? "Syncthing will also attempt to remove its internal " + ".stfolder marker. " : "") + "Rejoining the same remote folder requires this exact Folder ID." : "Forget this unlinked folder?";
        }
        confirmText: "Forget"
        background: Color.background
        foreground: root.controller.foreground
        selectedText: root.controller.urgent
        fontFamily: root.controller.fontFamily
        onCanceled: {
            root.controller.forgetConfirmOpen = false;
            root.controller.forgetFolderId = "";
        }
        onConfirmed: root.controller.confirmForget()
    }

    SelfRemovalDialog {
        id: removalDialog
        parent: keyCatcher
        anchors.fill: parent
        opened: root.controller.removalConfirmOpen
        busy: root.controller.syncthing ? root.controller.syncthing.settingsBusy : false
        fontFamily: root.controller.fontFamily
        z: 11
        onCanceled: root.controller.removalConfirmOpen = false
        onRemoveRequested: function (deletePluginSettings) {
            root.controller.requestSelfRemoval(deletePluginSettings);
        }
    }
}
