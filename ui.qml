import QtQuick 2.7
import QtQuick.Controls 2.0
import QtQuick.Layouts 1.3
import QtQuick.Controls.Material 2.2
import Vedder.vesc.utility 1.0
import Vedder.vesc.commands 1.0
import Vedder.vesc.configparams 1.0

Item {
    id: mainItem
    anchors.fill: parent
    anchors.margins: 5
    clip: true

    property Commands mCommands: VescIf.commands()
    property ConfigParams mMcConf: VescIf.mcConfig()

    // For building this package
    property string version: "@VERSION@"

    // layout tweaks, all gaps are fractions of the screen height so they work on any aspect ratio
    property real speedScale: 0.97         // landscape: main gauge size, 1.0 = full height
    property real portraitMainFrac: 0.44   // portrait: main gauge size as a fraction of the gauge area height
    property real smallOverlap: 0.06       // landscape: small gauges may overlap vertically by this much, 0 = touching
    property real gaugeGap: 0              // shrinks every small gauge by this many units
    property real areaMargin: ui * 0.01    // landscape: margin around the gauge area
    property real speedGap: ui * 0.01      // landscape: main gauge <-> small gauge grid
    property real barGap: ui * 0.025       // landscape: small gauge grid <-> battery bar
    property real textGap: ui * 0.03       // landscape: battery bar <-> status text
    property real barMargin: ui * 0.05     // landscape: battery bar top and bottom margin
    property real textMargin: barMargin + ui * 0.01  // landscape: status text top and bottom margin
    property real portraitMargin: ui * 0.02 // portrait: margin around the gauge area

    // gauge sweep angles in degrees, 0 = top, positive = clockwise
    property real defHalf: 140             // normal gauges sweep from -140 to 140
    property real outerHalf: 120           // portrait outer gauges, smaller = bigger gap facing the middle gauge
    property bool mirrorRight: true        // right gauges count the other way, like the stock duty gauge

    // page and orientation
    property int page: 0                  // 0 = dashboard, 1 = settings
    property int orient: 0                // 0 = auto, 1 = landscape, 2 = portrait
    property bool portrait: orient === 0 ? width < height : orient === 2
    property real ui: Math.min(width, height)
    property real fs: portrait ? 0.6 : 1.0
    property real sfont: Math.max(16, ui * 0.035)
    property real statusH: width * 0.28   // portrait: battery bar and status row

    // units, changed on the settings page
    property bool imperial: false
    property real distK: imperial ? 0.621371 : 1.0   // km -> display distance

    // colors
    property color baseColor: "#38b2ea"      // default gauge color and "temp ok"
    property color ampColor: "#c9b72e"       // all amp gauges
    property color dutyColor: "#8b44c4"      // duty gauge
    property color tempWarnColor: "#e8c21a"  // temp between start and cutoff
    property color tempHotColor: "#e03131"   // temp at or above the cutoff

    // gauge catalog, ids and names are in the same order
    property var gaugeIds: ["speed", "phase", "line", "weak", "duty", "tempEsc", "tempMotor",
                            "power", "battery", "voltage", "consump", "range"]
    property var gaugeNames: ["Speed", "Phase current", "Line current", "Field weakening", "Duty",
                              "Temp ESC", "Temp motor", "Power", "Battery", "Voltage",
                              "Consumption", "Range"]

    // predefined layouts: edit or add your own, the first one is used at startup
    property var presets: [
        { name: "Full",       main: "speed",   slots: ["phase", "line", "weak", "duty", "tempEsc", "tempMotor"] },
        { name: "Ride",       main: "speed",   slots: ["power", "range", "battery", "line", "tempEsc", "tempMotor"] },
        { name: "Tuning",     main: "speed",   slots: ["phase", "line", "weak", "duty", "power", "tempEsc"] },
        { name: "Efficiency", main: "consump", slots: ["speed", "power", "range", "battery", "line", "voltage"] }
    ]
    property int layoutIndex: 0           // -1 = custom
    property string mainGauge: presets[0].main
    property var slotGauges: presets[0].slots.slice()

    // live values
    property real kmh: 0
    property real ampsPhase: 0
    property real ampsBatt: 0
    property real ampsFw: 0
    property real dutyPct: 0
    property real tempMos: 0
    property real tempMotor: 0
    property real volts: 0
    property real battPct: 0
    property real whPerKm: 0
    property real range: 0

    // pack and limits, overwritten from the controller config when found
    property int cells: 14
    property real cellMin: 3.0
    property real cellMax: 4.2
    property real speedMaxKm: 60
    property real rangeMaxKm: 100
    property real minPhase: -100
    property real maxPhase: 100
    property real maxBattIn: 60
    property real maxBattRegen: -30
    property real maxFw: 60
    property real tempMosStart: 85
    property real tempMosEnd: 100
    property real tempMosMax: 100
    property real tempMotorStart: 85
    property real tempMotorEnd: 100
    property real tempMotorMax: 100
    property real phaseLim: Math.max(maxPhase, -minPhase)
    property real lineLim: Math.max(maxBattIn, -maxBattRegen)
    property real powerLim: Math.max(1000, Math.ceil(maxBattIn * cells * cellMax / 1000) * 1000)
    property real speedMaxDisp: Math.ceil(speedMaxKm * distK / 10) * 10
    property real rangeMaxDisp: Math.ceil(rangeMaxKm * distK / 50) * 50

    // range estimate
    property real packAh: 10
    property real packWh: packAh * cells * 3.6   // 3.6 V nominal per cell
    property real whAvg: 0                        // slow average of Wh/km, used only for range
    property bool whAvgValid: false

    // set true to use the firmware's own battery level instead of the voltage estimate
    property bool useFwLevel: false
    property real fwLevel: -1
    property bool configRead: false

    // smallest clean label step that divides both ends of the range and gives at most n intervals
    function stepFor(lo, hi, n) {
        var cand = [2, 5, 10, 15, 20, 25, 30, 50, 100, 200, 250, 500, 1000, 2000]
        var r = hi - lo
        var best = 10
        for (var i = 0; i < cand.length; i++) {
            var s = cand[i]
            if (lo % s !== 0 || hi % s !== 0) continue
            best = s
            if (r / s <= n) return s
        }
        return best
    }

    function roundUp10(x) { return Math.ceil(x / 10) * 10 }
    function roundUp20(x) { return Math.ceil(x / 20) * 20 }

    function tempColor(t, start, end) {
        if (t >= end) return tempHotColor
        if (t >= start) return tempWarnColor
        return baseColor
    }

    // everything a gauge needs, by catalog id
    function gDef(g) {
        switch (g) {
        case "speed":
            return { type: "SPEED", unit: imperial ? "MPH" : "KM/H", lo: 0, hi: speedMaxDisp,
                     v: kmh * distK, c: baseColor, n: 10 }
        case "phase":
            return { type: "PHASE", unit: "A", lo: -phaseLim, hi: phaseLim,
                     v: ampsPhase, c: ampColor, n: 8 }
        case "line":
            return { type: "LINE", unit: "A", lo: -lineLim, hi: lineLim,
                     v: ampsBatt, c: ampColor, n: 8 }
        case "weak":
            return { type: "WEAK", unit: "A", lo: -maxFw, hi: maxFw,
                     v: ampsFw, c: ampColor, n: 8 }
        case "duty":
            return { type: "DUTY", unit: "%", lo: -100, hi: 100,
                     v: dutyPct, c: dutyColor, n: 8 }
        case "tempEsc":
            return { type: "TEMP\nESC", unit: "°C", lo: 0, hi: tempMosMax,
                     v: tempMos, c: tempColor(tempMos, tempMosStart, tempMosEnd), n: 10 }
        case "tempMotor":
            return { type: "TEMP\nMOTOR", unit: "°C", lo: 0, hi: tempMotorMax,
                     v: tempMotor, c: tempColor(tempMotor, tempMotorStart, tempMotorEnd), n: 10 }
        case "power":
            return { type: "POWER", unit: "W", lo: -powerLim, hi: powerLim,
                     v: volts * ampsBatt, c: baseColor, n: 8 }
        case "battery":
            return { type: "BATTERY", unit: "%", lo: 0, hi: 100, v: battPct,
                     c: battPct < 15 ? tempHotColor : (battPct < 30 ? tempWarnColor : baseColor), n: 8 }
        case "voltage":
            return { type: "VOLT", unit: "V",
                     lo: Math.floor(cells * cellMin / 5) * 5, hi: Math.ceil(cells * cellMax / 5) * 5,
                     v: volts, c: baseColor, n: 8 }
        case "consump":
            return { type: "CONSUMP.", unit: imperial ? "WH/MI" : "WH/KM", lo: -50,
                     hi: Math.ceil(150 / distK / 50) * 50,
                     v: whPerKm / distK, c: baseColor, n: 8 }
        case "range":
            return { type: "RANGE", unit: imperial ? "MI" : "KM", lo: 0, hi: rangeMaxDisp,
                     v: Math.min(range * distK, rangeMaxDisp), c: baseColor, n: 10 }
        }
        return { type: "?", unit: "", lo: 0, hi: 100, v: 0, c: baseColor, n: 8 }
    }

    // layout helpers
    function applyPreset(i) {
        layoutIndex = i
        mainGauge = presets[i].main
        slotGauges = presets[i].slots.slice()
    }

    function gaugeAt(i) {
        return i === 0 ? mainGauge : slotGauges[i - 1]
    }

    function setGauge(i, g) {
        layoutIndex = -1
        if (i === 0) {
            mainGauge = g
        } else {
            var a = slotGauges.slice()
            a[i - 1] = g
            slotGauges = a
        }
    }

    function cycleGauge(i, dir) {
        var n = gaugeIds.length
        var cur = gaugeIds.indexOf(gaugeAt(i))
        setGauge(i, gaugeIds[(cur + dir + n) % n])
    }

    function nameOf(g) {
        var k = gaugeIds.indexOf(g)
        return k >= 0 ? gaugeNames[k] : g
    }

    // gauge geometry inside gaugeArea, index 0 = main gauge, 1 to 6 = small gauges
    function mainSizeF() {
        var W = gaugeArea.width
        var H = gaugeArea.height
        if (portrait) return Math.max(0, Math.min(W * 0.95, H * portraitMainFrac))
        return Math.max(0, Math.min(W, H) * speedScale)
    }

    function slotSize(i) {
        var W = gaugeArea.width
        var H = gaugeArea.height
        var m = mainSizeF()
        if (i === 0) return m
        if (portrait) {
            var rh = (H - m) / 2
            return Math.max(0, Math.min(rh - gaugeGap, W * 0.42))
        }
        var cw = (W - m - speedGap) / 3
        var ch = H / 2
        return Math.max(0, Math.min(cw, ch * (1 + smallOverlap)) - gaugeGap)
    }

    function slotX(i) {
        var W = gaugeArea.width
        var m = mainSizeF()
        var s = slotSize(i)
        if (i === 0) return portrait ? (W - m) / 2 : 0
        var col = (i - 1) % 3
        if (portrait) return col * (W - s) / 2        // outer gauges touch the edges, middle one overlaps
        var left = m + speedGap
        var cw = (W - left) / 3
        return left + col * cw + (cw - s) / 2
    }

    function slotY(i) {
        var H = gaugeArea.height
        var m = mainSizeF()
        var s = slotSize(i)
        if (i === 0) return (H - m) / 2
        var row = Math.floor((i - 1) / 3)
        if (portrait) {
            var rh = (H - m) / 2
            return row === 0 ? (rh - s) / 2 : H - rh + (rh - s) / 2
        }
        var ch = H / 2
        return row * ch + (ch - s) / 2
    }

    function readConfig() {
        var c = mMcConf.getParamInt("si_battery_cells")
        if (c > 0) cells = c
        var v
        v = mMcConf.getParamDouble("si_battery_ah");        if (v > 0) packAh = v
        v = mMcConf.getParamDouble("l_current_max");        if (v > 0) maxPhase = roundUp20(v * 1.15)
        v = mMcConf.getParamDouble("l_current_min");        if (v < 0) minPhase = -roundUp20(-v * 1.15)
        v = mMcConf.getParamDouble("l_in_current_max");     if (v > 0) maxBattIn = roundUp20(v * 1.15)
        v = mMcConf.getParamDouble("l_in_current_min");     if (v < 0) maxBattRegen = -roundUp20(-v * 1.15)
        v = mMcConf.getParamDouble("foc_fw_current_max");   if (v > 0) maxFw = roundUp20(v * 1.15)
        v = mMcConf.getParamDouble("l_temp_fet_start");     if (v > 0) tempMosStart = v
        v = mMcConf.getParamDouble("l_temp_fet_end");       if (v > 0) { tempMosEnd = v; tempMosMax = Math.max(100, roundUp10(v)) }
        v = mMcConf.getParamDouble("l_temp_motor_start");   if (v > 0) tempMotorStart = v
        v = mMcConf.getParamDouble("l_temp_motor_end");     if (v > 0) { tempMotorEnd = v; tempMotorMax = Math.max(100, roundUp10(v)) }
        configRead = true
    }

    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            mCommands.getValues()
            mCommands.getValuesSetup()
        }
    }

    Connections {
        target: mCommands

        onValuesReceived: {
            if (!configRead) readConfig()

            var poles = mMcConf.getParamInt("si_motor_poles")
            var gear = mMcConf.getParamDouble("si_gear_ratio")
            var wheel = mMcConf.getParamDouble("si_wheel_diameter")
            var ms = (values.rpm / (poles / 2) / gear) * Math.PI * wheel / 60
            kmh = Math.abs(ms * 3.6)

            ampsPhase = values.current_motor
            ampsBatt = values.current_in
            ampsFw = -values.id
            dutyPct = values.duty_now * 100      // signed
            tempMos = values.temp_mos
            tempMotor = values.temp_motor

            // grow gauge ranges if the real value goes past them
            if (kmh > speedMaxKm) speedMaxKm = roundUp10(kmh * 1.1)
            if (ampsPhase > maxPhase) maxPhase = roundUp20(ampsPhase * 1.1)
            if (ampsPhase < minPhase) minPhase = -roundUp20(-ampsPhase * 1.1)
            if (ampsBatt > maxBattIn) maxBattIn = roundUp20(ampsBatt * 1.1)
            if (ampsBatt < maxBattRegen) maxBattRegen = -roundUp20(-ampsBatt * 1.1)
            if (Math.abs(ampsFw) > maxFw) maxFw = roundUp20(Math.abs(ampsFw) * 1.1)

            // low-pass the voltage so sag under load doesn't make the bar jump
            volts = volts === 0 ? values.v_in : volts * 0.9 + values.v_in * 0.1

            if (useFwLevel && fwLevel >= 0) {
                battPct = fwLevel * 100
            } else {
                var vMin = cells * cellMin
                var vMax = cells * cellMax
                battPct = Math.max(0, Math.min(100, (volts - vMin) / (vMax - vMin) * 100))
            }

            if (kmh > 3) {
                var inst = (values.v_in * values.current_in) / kmh
                whPerKm = inst
                // about 20 s time constant at 10 Hz, so range doesn't jump with every throttle blip
                if (!whAvgValid) { whAvg = inst; whAvgValid = true }
                else whAvg = whAvg * 0.995 + inst * 0.005
            }
            var remainingWh = packWh * battPct / 100
            range = (whAvgValid && whAvg > 5) ? remainingWh / whAvg : 0

            var rr = Math.min(range, 500)
            if (rr > rangeMaxKm) rangeMaxKm = Math.ceil(rr * 1.1 / 50) * 50
        }

        onValuesSetupReceived: {
            fwLevel = values.battery_level
        }
    }

    // dashboard page
    Item {
        id: dashPage
        anchors.fill: parent
        visible: page === 0

        Item {
            id: gaugeArea
            x: portrait ? portraitMargin : areaMargin
            y: portrait ? portraitMargin : areaMargin
            width: portrait ? mainItem.width - 2 * portraitMargin
                            : battBar.x - barGap - areaMargin
            height: portrait ? mainItem.height - statusH - 2 * portraitMargin
                             : mainItem.height - 2 * areaMargin
            Repeater {
                model: 7
                CustomGauge {
                    property string gid: gaugeAt(index)
                    property var d: gDef(gid)
                    property real sz: slotSize(index)
                    property int col: index > 0 ? (index - 1) % 3 : 1   // 0 = left, 1 = middle, 2 = right
                    x: slotX(index)
                    y: slotY(index)
                    z: (index === 2 || index === 5) ? 1 : 0   // middle gauges overlap on top in portrait
                    width: sz
                    height: sz
                    visible: sz > 20
                    minAngle: portrait && col === 0 ? 270 - outerHalf
                              : (portrait && col === 2 ? (mirrorRight ? 90 + outerHalf : 90 - outerHalf)
                                                       : -defHalf)
                    maxAngle: portrait && col === 0 ? 270 + outerHalf
                              : (portrait && col === 2 ? (mirrorRight ? 90 - outerHalf : 90 + outerHalf)
                                                       : defHalf)
                    minimumValue: d.lo
                    maximumValue: d.hi
                    labelStep: stepFor(d.lo, d.hi, d.n)
                    tickmarkScale: 1
                    nibColor: d.c
                    value: d.v
                    unitText: d.unit
                    typeText: d.type
                }
            }

            // gear button, opens the settings page
            Rectangle {
                id: gearBtn
                z: 5
                width: Math.max(32, mainItem.ui * 0.11)
                height: width
                radius: width / 2
                color: gearMouse.pressed ? "#555" : "#3a3a3a"
                border.color: "#555"
                border.width: 2
                x: slotX(0) + slotSize(0) * 0.10
                y: slotY(0) + slotSize(0) - height - slotSize(0) * 0.08

                Image {
                    id: gearImg
                    anchors.centerIn: parent
                    width: parent.width * 0.6
                    height: width
                    source: "qrc:/res/icons/Settings-96.png"
                    fillMode: Image.PreserveAspectFit
                }
                Text {
                    anchors.centerIn: parent
                    visible: gearImg.status !== Image.Ready
                    text: "\u2699"
                    color: "#ddd"
                    font.pixelSize: parent.width * 0.6
                }
                MouseArea {
                    id: gearMouse
                    anchors.fill: parent
                    onClicked: page = 1
                }
            }
        }

        Rectangle {
            id: battBar
            property int segments: 10          // number of blocks
            property real segGap: Math.max(2, mainItem.ui * 0.006)   // space between blocks

            width: portrait ? mainItem.width - 24 : Math.max(14, mainItem.ui * 0.045)
            height: portrait ? Math.max(16, mainItem.width * 0.04) : mainItem.height - 2 * barMargin
            x: portrait ? 12 : textCol.x - textGap - width
            y: portrait ? mainItem.height - statusH + 4 : barMargin
            color: "#222"
            border.color: "#555"
            border.width: Math.max(2, mainItem.ui * 0.005)
            radius: 5

            Grid {
                anchors.fill: parent
                anchors.margins: battBar.border.width + 2
                columns: portrait ? battBar.segments : 1
                spacing: battBar.segGap
                Repeater {
                    model: battBar.segments
                    Rectangle {
                        property int level: portrait ? index : battBar.segments - 1 - index   // 0 = lowest block
                        property real t: 1 - level / (battBar.segments - 1)                    // 0 = light, 1 = dark
                        width: portrait ? (parent.width - (battBar.segments - 1) * battBar.segGap) / battBar.segments
                                        : parent.width
                        height: portrait ? parent.height
                                         : (parent.height - (battBar.segments - 1) * battBar.segGap) / battBar.segments
                        radius: 0
                        color: battPct > level * (100 / battBar.segments)
                               ? Qt.rgba(0.247 - 0.204 * t, 0.722 - 0.177 * t, 0.937 - 0.215 * t, 1)
                               : "#2c2c2c"
                    }
                }
            }
        }

        Item {
            id: textCol
            clip: true
            width: portrait ? mainItem.width : mainItem.width * 0.17
            height: portrait ? statusH - battBar.height - 20 : mainItem.height - 2 * textMargin
            x: portrait ? 0 : mainItem.width - width
            y: portrait ? battBar.y + battBar.height + 10 : textMargin

            property color labelColor: "#ddd"
            property color valueColor: "#ddd"
            property color unitColor: "#ddd"
            property var labels: ["BATTERY", "VOLTAGE", "RANGE", "CONSUMPTION"]
            property var units: ["%", "V", imperial ? "MI" : "KM", imperial ? "WH/MI" : "WH/KM"]

            function valueFor(i) {
                if (i === 0) return battPct.toFixed(0)
                if (i === 1) return volts.toFixed(2)
                if (i === 2) return range > 0 ? Math.min(range * distK, 999).toFixed(0) : "--"
                return (whPerKm / distK).toFixed(0)
            }

            Repeater {
                model: 4
                Column {
                    x: portrait ? index * (textCol.width / 4) + 12 : 0
                    y: portrait ? 0 : index * (textCol.height - height) / 3
                    spacing: 0

                    Text {
                        text: textCol.labels[index]
                        color: textCol.labelColor
                        font.pixelSize: Math.max(11, mainItem.ui * 0.034 * fs)
                    }
                    Row {
                        spacing: portrait ? 6 : 10
                        Text {
                            id: valText
                            text: textCol.valueFor(index)
                            color: textCol.valueColor
                            font.pixelSize: Math.max(18, mainItem.ui * 0.085 * fs)
                        }
                        Text {
                            text: textCol.units[index]
                            color: textCol.unitColor
                            font.pixelSize: Math.max(12, mainItem.ui * 0.045 * fs)
                            anchors.baseline: valText.baseline
                        }
                    }
                }
            }
        }
    }

    // settings page
    Rectangle {
        id: settingsPage
        anchors.fill: parent
        visible: page === 1
        color: "#262626"

        Flickable {
            anchors.fill: parent
            anchors.margins: 16
            contentWidth: width
            contentHeight: setCol.height + 30
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: setCol
                width: parent.width
                spacing: 18

                Row {
                    spacing: 20
                    Button {
                        text: "Back"
                        font.pixelSize: sfont
                        onClicked: page = 0
                    }
                    Text {
                        text: "Layout: " + (layoutIndex >= 0 ? presets[layoutIndex].name : "Custom")
                        color: "#ddd"
                        font.pixelSize: sfont * 1.2
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Text { text: "Predefined layouts"; color: "#aaa"; font.pixelSize: sfont }
                Flow {
                    width: setCol.width
                    spacing: 10
                    Repeater {
                        model: presets.length
                        Button {
                            text: presets[index].name
                            font.pixelSize: sfont
                            highlighted: layoutIndex === index
                            onClicked: applyPreset(index)
                        }
                    }
                }

                Text {
                    text: "Gauges (1 to 3 top row, 4 to 6 bottom row)"
                    color: "#aaa"
                    font.pixelSize: sfont
                }
                Repeater {
                    model: 7
                    Row {
                        spacing: 12
                        Text {
                            width: sfont * 8
                            text: index === 0 ? "Main gauge" : "Gauge " + index
                            color: "#ddd"
                            font.pixelSize: sfont
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Button {
                            text: "<"
                            font.pixelSize: sfont
                            onClicked: cycleGauge(index, -1)
                        }
                        Text {
                            width: sfont * 10
                            horizontalAlignment: Text.AlignHCenter
                            text: nameOf(gaugeAt(index))
                            color: "#ddd"
                            font.pixelSize: sfont
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Button {
                            text: ">"
                            font.pixelSize: sfont
                            onClicked: cycleGauge(index, 1)
                        }
                    }
                }

                Text { text: "Orientation"; color: "#aaa"; font.pixelSize: sfont }
                Flow {
                    width: setCol.width
                    spacing: 10
                    Button { text: "Auto"; font.pixelSize: sfont; highlighted: orient === 0; onClicked: orient = 0 }
                    Button { text: "Landscape"; font.pixelSize: sfont; highlighted: orient === 1; onClicked: orient = 1 }
                    Button { text: "Portrait"; font.pixelSize: sfont; highlighted: orient === 2; onClicked: orient = 2 }
                }

                Switch {
                    text: "Imperial units (mph, mi)"
                    font.pixelSize: sfont
                    checked: imperial
                    onClicked: imperial = checked
                }

                Row {
                    spacing: 12
                    Text {
                        width: sfont * 10
                        text: "Cells in series"
                        color: "#ddd"
                        font.pixelSize: sfont
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Button { text: "-"; font.pixelSize: sfont; onClicked: cells = Math.max(1, cells - 1) }
                    Text {
                        width: sfont * 3
                        horizontalAlignment: Text.AlignHCenter
                        text: cells
                        color: "#ddd"
                        font.pixelSize: sfont
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Button { text: "+"; font.pixelSize: sfont; onClicked: cells = Math.min(40, cells + 1) }
                }

                Row {
                    spacing: 12
                    Text {
                        width: sfont * 10
                        text: "Pack capacity (Ah)"
                        color: "#ddd"
                        font.pixelSize: sfont
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Button { text: "-"; font.pixelSize: sfont; onClicked: packAh = Math.max(0.5, packAh - 0.5) }
                    Text {
                        width: sfont * 3
                        horizontalAlignment: Text.AlignHCenter
                        text: packAh.toFixed(1)
                        color: "#ddd"
                        font.pixelSize: sfont
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Button { text: "+"; font.pixelSize: sfont; onClicked: packAh = Math.min(500, packAh + 0.5) }
                }
            }
        }
    }
}