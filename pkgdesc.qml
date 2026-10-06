import QtQuick 2.15

Item {
    property string pkgName: "Custom dashboard"
    property string pkgDescriptionMd: "README.md"
    property string pkgLisp: ""
    property string pkgQml: "ui.qml"
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "dashboard.vescpkg"

    function isCompatible(fwRxParams) {
        return true
    }
}