import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../"
import "../reusables"

Popup {
    id: updatePopup
    parent: rootObj ? rootObj : undefined
    x: parent && parent.width > 0 ? Math.max(0, Math.round((parent.width - width) / 2)) : 0
    y: parent && parent.height > 0 ? Math.max(0, Math.round((parent.height - height) / 2)) : 0
    width: rootObj ? Math.min(rootObj.width - rootObj.s(32), rootObj.s(620)) : 620
    modal: true
    dim: true
    padding: rootObj ? rootObj.s(20) : 20
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

    property var rootObj
    property var releases: []
    property bool loading: false
    property string selectedVersion: ""
    signal installRequested(string version)

    function openFor(items, isLoading) {
        releases = items || [];
        loading = isLoading;
        selectedVersion = releases.length > 0 ? releases[0].version : "";
        open();
    }

    function setReleases(items) {
        releases = items || [];
        loading = false;
        if (selectedVersion === "" && releases.length > 0) selectedVersion = releases[0].version;
    }

    background: Rectangle {
        radius: ThemeBackend.clampedBorderRadius
        color: popupGlass.active ? "transparent" : ThemeBackend.base
        GlassFill {
            id: popupGlass
            anchors.fill: parent
            radius: parent.radius
            tintColor: ThemeBackend.base
            tintAmount: 0.25
        }
    }

    contentItem: ColumnLayout {
        spacing: rootObj ? rootObj.s(14) : 14

        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: "Mises a jour disponibles"
                color: ThemeBackend.text
                font.family: ThemeBackend.fontFamily
                font.pixelSize: rootObj ? rootObj.s(18) : 18
                font.bold: true
            }
            CloseButton {
                size: rootObj ? rootObj.s(30) : 30
                cornerRadius: ThemeBackend.borderRadius
                onClicked: updatePopup.close()
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Choisis une version plus recente que la tienne. Les notes affichent aussi les changements intermediaires."
            wrapMode: Text.WordWrap
            color: ThemeBackend.subtext0
            font.family: ThemeBackend.fontFamily
            font.pixelSize: rootObj ? rootObj.s(12) : 12
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: rootObj ? rootObj.s(300) : 300
            clip: true

            Text {
                anchors.centerIn: parent
                visible: updatePopup.loading
                text: "Recherche des versions..."
                color: ThemeBackend.subtext0
                font.family: ThemeBackend.fontFamily
            }

            Text {
                anchors.centerIn: parent
                visible: !updatePopup.loading && updatePopup.releases.length === 0
                text: "Aucune mise a jour disponible."
                color: ThemeBackend.subtext0
                font.family: ThemeBackend.fontFamily
            }

            ListView {
                anchors.fill: parent
                visible: !updatePopup.loading && updatePopup.releases.length > 0
                clip: true
                spacing: rootObj ? rootObj.s(8) : 8
                model: updatePopup.releases
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width - (rootObj ? rootObj.s(6) : 6)
                    height: details.implicitHeight + (rootObj ? rootObj.s(22) : 22)
                    radius: ThemeBackend.borderRadius
                    color: updatePopup.selectedVersion === modelData.version
                        ? Qt.alpha(ThemeBackend.mauve, 0.2) : ThemeBackend.surface0
                    border.width: updatePopup.selectedVersion === modelData.version ? 1 : 0
                    border.color: ThemeBackend.mauve

                    MouseArea {
                        anchors.fill: parent
                        onClicked: updatePopup.selectedVersion = modelData.version
                    }

                    ColumnLayout {
                        id: details
                        anchors.fill: parent
                        anchors.margins: rootObj ? rootObj.s(11) : 11
                        spacing: rootObj ? rootObj.s(5) : 5
                        Text {
                            Layout.fillWidth: true
                            text: "v" + modelData.version + (updatePopup.selectedVersion === modelData.version ? "  — selectionnee" : "")
                            color: ThemeBackend.text
                            font.family: ThemeBackend.fontFamily
                            font.bold: true
                            font.pixelSize: rootObj ? rootObj.s(14) : 14
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.notes === "" ? "Aucune note de version." : modelData.notes
                            color: ThemeBackend.subtext0
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj ? rootObj.s(11) : 11
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            ClickButton {
                implicitHeight: rootObj ? rootObj.s(36) : 36
                buttonText: "Annuler"
                accentColor: ThemeBackend.surface0
                textColor: ThemeBackend.text
                cornerRadius: ThemeBackend.borderRadius
                onTriggered: updatePopup.close()
            }
            FillButton {
                implicitHeight: rootObj ? rootObj.s(36) : 36
                enabled: !updatePopup.loading && updatePopup.selectedVersion !== ""
                opacity: enabled ? 1.0 : 0.5
                buttonText: updatePopup.selectedVersion === "" ? "Installer" : "Installer v" + updatePopup.selectedVersion
                buttonIcon: "󰚰"
                accentColor: ThemeBackend.green
                baseColor: ThemeBackend.surface0
                hoverColor: Qt.alpha(ThemeBackend.green, 0.15)
                textColor: ThemeBackend.green
                filledTextColor: ThemeBackend.crust
                cornerRadius: ThemeBackend.borderRadius
                onTriggered: {
                    let version = updatePopup.selectedVersion;
                    updatePopup.close();
                    updatePopup.installRequested(version);
                }
            }
        }
    }
}
