import QtQuick 2.7
import QtQuick.Controls 2.10
import QtQuick.Layouts 1.3
import QtQuick.Controls.Material 2.2
import Vedder.vesc.utility 1.0
import Vedder.vesc.commands 1.0
import Vedder.vesc.configparams 1.0

Item {
    id: mainItem
    anchors.fill: parent
    anchors.margins: 0
    clip: true

    property Commands mCommands: VescIf.commands()
    property ConfigParams mMcConf: VescIf.mcConfig()

    // current Build version, like "v1.0.0"
    property string version: "@VERSION@"

    // same background as the stock RT Data page
    Rectangle {
        anchors.fill: parent
        color: Utility.getAppHexColor("darkBackground")
    }

    // layout tweaks, all gaps are fractions of the screen height so they work on any aspect ratio
    property real speedScale: 0.97         // landscape: main gauge size, 1.0 = full height
    property real portraitMainFrac: 0.46   // portrait: main gauge size as a fraction of the gauge area height
    property real smallOverlap: 0.06       // landscape: small gauges may overlap vertically by this much, 0 = touching
    property real gaugeGap: 0              // shrinks every small gauge by this many units
    property real areaMargin: ui * 0.01    // landscape: margin around the gauge area
    property real speedGap: ui * 0.01      // landscape: main gauge <-> small gauge grid
    property real barGap: ui * 0.025       // landscape: small gauge grid <-> battery bar
    property real textGap: ui * 0.03       // landscape: battery bar <-> status text
    property real barMargin: ui * 0.05     // landscape: battery bar top and bottom margin
    property real textMargin: barMargin + ui * 0.01  // landscape: status text top and bottom margin
    property real outerGaugeStagger: ui * 0.040 // stagger the outer gauges to recreate the orignal design

    // portrait spacing, matched to the stock RT Data page
    property real portraitMargin: ui * 0.02   // portrait: side margin around the gauge area
    property real topPad: ui * 0.03           // portrait: space above the first gauge row
    property real bottomPad: ui * 0.02        // portrait: space below the status text
    property real gaugeBarGap: ui * 0.02      // portrait: space between the last gauge row and the battery bar
    property real barTextGap: ui * 0.012      // portrait: space between the battery bar and the status text
    property real barH: Math.max(16, width * 0.04)   // portrait: battery bar height

    // gauge sweep angles in degrees, 0 = top, positive = clockwise
    property real defHalf: 140        // normal gauges sweep from -140 to 140
    property real gapMargin: 25       // portrait outer gauges: extra clearance in degrees beyond the middle gauge's overlap
    property real minOuterHalf: 115   // narrowest allowed half sweep
    property real maxOuterHalf: 140   // widest allowed half sweep, same as the normal gauges
    property bool mirrorRight: true   // right gauges count the other way, like the stock duty gauge

    // page and orientation
    property var dialogParent: ApplicationWindow.overlay
    property var settingsSnap: null
    property int orient: 0            // 0 = auto, 1 = landscape, 2 = portrait
    property bool portrait: orient === 0 ? width < height : orient === 2
    property real ui: Math.min(width, height)
    property real fs: portrait ? 0.6 : 1.0
    property int gaugeCount: 7

    // portrait: height of the status text block and of everything below the gauges
    property real statusTextH: (Math.max(11, ui * 0.034 * fs) + Math.max(18, ui * 0.085 * fs)) * 1.3
    property real statusH: barH + gaugeBarGap + barTextGap + statusTextH + bottomPad

    // really a fix for a unreproducible bug, wrong gauge colors after orientation rotation
    onPortraitChanged: {
        gaugeCount = 0
        rebuildTimer.restart()
    }

    // rebuilding gauges on an interval to fix incorrect coloring during orientation changes
    Timer {
        id: rebuildTimer
        interval: 60
        onTriggered: gaugeCount = 7
    }

    // units, changed on the settings page
    property bool imperial: false
    property real distK: imperial ? 0.621371 : 1.0 // or that 1.60934
    property bool tempF: false

    // colors
    property color baseColor: "#38b2ea"      // default gauge color and "temp ok"
    property color ampColor: "#c9b72e"       // all amp gauges
    property color dutyColor: "#8b44c4"      // duty gauge
    property color tempWarnColor: "#e8c21a"  // low battery warning
    property color orangeColor: Utility.getAppHexColor("orange") // temp above 40 (hardcoded but ok)
    property color tempHotColor: "#e03131"   // temp above the throttle start

    // gauge catalog, ids and names are in the same order
    property var gaugeIds: ["speed", "erpm", "phase", "line", "weak", "duty",
                            "mod", "id", "iq", "vd", "vq", "vdq",
                            "tempEsc", "tempMotor", "power", "battery", "voltage", "consump", "range"]
    property var gaugeNames: ["Speed", "ERPM", "Phase current", "Line current", "Field weakening", "Duty",
                              "Modulation depth", "Id", "Iq", "Vd", "Vq", "Vdq",
                              "Temp ESC", "Temp motor", "Power", "Battery", "Voltage",
                              "Consumption", "Range"]

    // layouts selectible in the settings menu
    property var presets: [
        // Default
        { name: "Main",      main: "speed",   slots: ["phase", "power", "line", "tempEsc", "mod", "tempMotor"] },

        // Mostly Amps, still good for riding
        { name: "Tuning",    main: "speed",   slots: ["phase", "line", "weak", "duty", "power", "mod"] },

        // Most Fardriver gauges in one
        { name: "Fardriver", main: "speed",   slots: ["erpm", "tempMotor", "power", "phase", "tempEsc", "line"] },

        // Volts and Amps displayed nicely
        { name: "Amps",      main: "speed",   slots: ["phase", "line", "weak", "tempEsc", "duty", "tempMotor"] },
        { name: "Volts",     main: "speed",   slots: ["duty", "power", "mod", "vq", "voltage", "vd"] },

        // FOC / field weakening / overmodulation diagnostics
        { name: "FOC",       main: "mod",     slots: ["vq", "vdq", "vd", "iq", "duty", "id"] }
    ]
    property int layoutIndex: 0 // -1 = custom
    property string mainGauge: presets[0].main
    property var slotGauges: presets[0].slots.slice()

    // live values (using all these to make screenshots)
    property real kmh: 0
    property real kmhSigned: 0
    property bool negSpeed: false
    property real ampsPhase: 0
    property real ampsBatt: 0
    property real ampsFw: 0
    property real dutyPct: 0

    // raw FOC telemetry
    property real ampsId: 0
    property real ampsIq: 0
    property real voltsD: 0
    property real voltsQ: 0
    property real voltsRaw: 0

    property real tempMos: 0
    property real tempMotor: 0
    property real volts: 0
    property real battPct: 0
    property real whPerKm: 0
    property real range: 0

    // bottom info row: 0 = battery / voltage / range / consumption, 1 = odometer / trip / up-time / energy
    property int statusMode: 0
    property real odoKm: 0
    property real tripKm: 0
    property real upMs: 0
    property real whNet: 0         // energy used, net of regen

    // magnitude of the d/q voltage vector
    property real voltsDQ: Math.sqrt(voltsD * voltsD + voltsQ * voltsQ)

    // normalized against the linear SVPWM voltage-vector limit.
    // 1.00 = linear modulation boundary, ~1.10 = six-step limit (2 * sqrt(3) / pi).
    property real modulationDepth: voltsRaw > 1.0
                                   ? voltsDQ / (voltsRaw / Math.sqrt(3.0))
                                   : 0

    // battery value used by the bar only, glides to the real value instead of jumping
    property real battShown: battPct
    Behavior on battShown {
        NumberAnimation { duration: 700; easing.type: Easing.OutCubic }
    }

    // pack and limits, overwritten from the controller config when found
    property int cells: 14
    property real cellMin: 3.0
    property real cellMax: 4.2
    property real speedMaxKm: 100
    property real rangeMaxKm: 350
    property real minPhase: -200
    property real maxPhase: 200
    property real maxBattIn: 100
    property real maxBattRegen: -100
    property real maxFw: 80
    property real tempMosStart: 85
    property real tempMosEnd: 100
    property real tempMosMax: 100
    property real tempMotorStart: 85
    property real tempMotorEnd: 100
    property real tempMotorMax: 100
    property real phaseLim: Math.max(maxPhase, -minPhase)
    property real lineLim: Math.max(maxBattIn, -maxBattRegen)
    property real powerLim: {
        var raw = maxBattIn * cells * cellMax
        return Math.max(1000, raw <= 4000 ? Math.ceil(raw / 1000) * 1000
                                          : Math.ceil(raw / 2000) * 2000)
    }

    // speed estimations, not used for anything but display gauges
    property real speedEstKm: 0       // estimated no-load top speed at the current voltage
    property real speedPeakKm: 0      // fastest speed since the package started
    property bool showSpeedEst: true  // small TOP / EST label on the main gauge
    property real erpm: 0
    property real erpmMax: 30000      // dial range, only grows

    // Id/Iq use the same dynamic scale as the phase-current gauge.
    property real dqCurrentLim: phaseLim

    // Voltage gauge scale: linear limit (Vdc / sqrt(3)) with room for the ~1.10 six-step limit
    // plus a little headroom, rounded to a limit with clean gauge labels.
    property real dqVoltageLim: Math.max(10, niceLim(cells * cellMax / Math.sqrt(3.0) * 1.15, 8))
    property real speedMaxDisp: Math.ceil(speedMaxKm * distK / 10) * 10
    property real rangeMaxDisp: Math.ceil(rangeMaxKm * distK / 50) * 50

    // range estimate
    property real packAh: 10
    property real packWh: packAh * cells * 3.6    // 3.6 V nominal per cell
    property real whAvg: 0                        // slow average of Wh/km, used only for range
    property bool whAvgValid: false

    // set true to use the firmware's own battery level instead of the voltage estimate (good)
    property bool useFwLevel: true
    property real fwLevel: -1
    property bool configRead: false

    // smallest clean label step that divides both ends of the range and gives at most n intervals
    function stepFor(lo, hi, n) {
        var cand = [2, 5, 10, 15, 20, 25, 30, 40, 50, 60, 100, 200, 250, 500, 1000, 2000]
        var r = hi - lo
        var best = -1
        var fit = 0
        for (var i = 0; i < cand.length; i++) {
            var s = cand[i]
            if (fit === 0 && r / s <= n) fit = s
            if (lo % s !== 0 || hi % s !== 0) continue
            best = s
            if (r / s <= n) return s
        }
        // nothing divides cleanly: take the closest step that gives a readable number of labels
        return (best > 0 && r / best <= n * 1.5) ? best : (fit > 0 ? fit : 10)
    }

    // smallest symmetric limit above raw that lands on a clean step with at most n intervals across -lim..lim
    function niceLim(raw, n) {
        var cand = [2, 5, 10, 15, 20, 25, 30, 40, 50, 60, 100, 200, 250, 500, 1000, 2000]
        for (var i = 0; i < cand.length; i++) {
            if (2 * raw / cand[i] <= n) return Math.ceil(raw / cand[i]) * cand[i]
        }
        return Math.ceil(raw / 2000) * 2000
    }

    function roundUp10(x) { return Math.ceil(x / 10) * 10 }
    function roundUp20(x) { return Math.ceil(x / 40) * 40 } // multiples of 40 always land on clean label steps, causes a bug if not

    function hms(ms) {
        var s = Math.max(0, Math.floor(ms / 1000))
        var h = Math.floor(s / 3600)
        var m = Math.floor((s % 3600) / 60)
        var sec = s % 60
        return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m + ":" + (sec < 10 ? "0" : "") + sec
    }

    // same as the function above, clean rounding of gauges
    function erpmRound(x) { return x <= 40000 ? Math.max(10000, Math.ceil(x / 10000) * 10000)
                                              : Math.ceil(x / 20000) * 20000 }
    function erpmStep(hi) { return hi <= 40000 ? 5000 : (hi <= 80000 ? 10000 : 20000) }

    // same rule as the stock dashboard: blue up to 40, orange up to the throttle start, red above it
    // t is always the raw value in °C
    function tempColor(t, start) {
        if (t > start) return tempHotColor
        if (t > 40) return orangeColor
        return baseColor
    }

    // temperatures default to °C, show °F when tempF is on
    function tempShow(c) { return tempF ? c * 1.8 + 32 : c }

    // gauge maximum: unchanged in °C, rounded up to a multiple of 40 in °F so labels look nice
    function tempHi(maxC) { return tempF ? Math.ceil((maxC * 1.8 + 32) / 40) * 40 : maxC }

    // everything a gauge needs, by catalog id, recycling colors is eco
    function gDef(g) {
        switch (g) {
        case "speed":
            return { type: "SPEED", unit: imperial ? "MPH" : "KM/H",
                     lo: negSpeed ? -speedMaxDisp : 0, hi: speedMaxDisp,
                     v: (negSpeed ? kmhSigned : kmh) * distK, c: baseColor, n: 10 }
        case "erpm":
            return { type: "ERPM", unit: "RPM", lo: 0, hi: erpmMax,
                     v: erpm, c: baseColor, n: 8, step: erpmStep(erpmMax), scale: 0.001, suffix: "k" }
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
        case "mod":
            // percent, 100 = end of linear modulation. never exactly 0, the gauge draws a blue needle there
            return { type: "MOD", unit: "%", lo: 0, hi: 120,
                     v: Math.max(0.01, modulationDepth * 100), c: dutyColor, n: 6, step: 20 }
        case "id":
            return { type: "ID", unit: "A", lo: -dqCurrentLim, hi: dqCurrentLim,
                     v: ampsId, c: ampColor, n: 8 }
        case "iq":
            return { type: "IQ", unit: "A", lo: -dqCurrentLim, hi: dqCurrentLim,
                     v: ampsIq, c: ampColor, n: 8 }
        case "vd":
            return { type: "VD", unit: "V", lo: -dqVoltageLim, hi: dqVoltageLim,
                     v: voltsD, c: baseColor, n: 8 }
        case "vq":
            return { type: "VQ", unit: "V", lo: -dqVoltageLim, hi: dqVoltageLim,
                     v: voltsQ, c: baseColor, n: 8 }
        case "vdq":
            return { type: "VDQ", unit: "V", lo: 0, hi: dqVoltageLim,
                     v: Math.max(0.01, voltsDQ), c: baseColor, n: 8 }
        case "tempEsc":
            return { type: "TEMP\nESC", unit: tempF ? "°F" : "°C", lo: 0, hi: tempHi(tempMosMax),
                     v: tempShow(tempMos), c: tempColor(tempMos, tempMosStart), n: 10 }
        case "tempMotor":
            return { type: "TEMP\nMOTOR", unit: tempF ? "°F" : "°C", lo: 0, hi: tempHi(tempMotorMax),
                     v: tempShow(tempMotor), c: tempColor(tempMotor, tempMotorStart), n: 10 }
        case "power":
            return { type: "POWER", unit: "W", lo: -powerLim, hi: powerLim,
                     v: volts * ampsBatt, c: baseColor, n: 8,
                     step: powerLim <= 4000 ? 1000 : 2000, scale: 0.001, suffix: "k" }
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
        var col = (i - 1) % 3
        var baseY
        if (portrait) {
            baseY = row === 0 ? 0 : H - s
        } else {
            var ch = H / 2
            baseY = row * ch + (ch - s) / 2
            }

        // Stagger the outer gauges in both orientations (weird now)
        if (portrait && (col === 0 || col === 2) || (!portrait)) {
            var offset = outerGaugeStagger
            return baseY + (row === 0 ? offset : -offset)
        }
        return baseY
    }

    // portrait outer gauges: direction and half-width (degrees) of the gap where the middle gauge covers the dial,
    // worked out from the real positions, so the stagger tilt is included
    function outerGap(i) {
        var mid = i <= 3 ? 2 : 5                    // the middle gauge in the same row
        var s = slotSize(i)
        var sm = slotSize(mid)
        if (s < 1) return { center: 90, half: 60 }
        var dx = (slotX(mid) + sm / 2) - (slotX(i) + s / 2)
        var dy = (slotY(mid) + sm / 2) - (slotY(i) + s / 2)
        var d = Math.sqrt(dx * dx + dy * dy)
        var r = s / 2
        var rm = sm / 2
        var center = Math.atan2(dx, -dy) * 180 / Math.PI      // 0 = up, clockwise
        if (center < 0) center += 360
        var phi = 0                                           // half-angle of the overlap seen from this gauge's center
        if (d > 0.001 && d < r + rm) {
            var c = (r * r + d * d - rm * rm) / (2 * r * d)
            phi = Math.acos(Math.max(-1, Math.min(1, c))) * 180 / Math.PI
        }
        var half = Math.max(180 - maxOuterHalf, Math.min(180 - minOuterHalf, phi + gapMargin))
        return { center: center, half: half }
    }

    // sweep start and end for the outer gauges, left side counts clockwise, right side mirrored
    function outerMinAngle(i) {
        var g = outerGap(i)
        if ((i - 1) % 3 === 0) return g.center + g.half
        return mirrorRight ? g.center - g.half : g.center + g.half - 360
    }

    function outerMaxAngle(i) {
        var g = outerGap(i)
        if ((i - 1) % 3 === 0) return g.center - g.half + 360
        return mirrorRight ? g.center + g.half - 360 : g.center - g.half
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
        // throttle start is rounded up to 5 like the stock dashboard does
        v = mMcConf.getParamDouble("l_temp_fet_start");     if (v > 0) tempMosStart = Math.ceil(v / 5) * 5
        v = mMcConf.getParamDouble("l_temp_fet_end");       if (v > 0) { tempMosEnd = v; tempMosMax = Math.max(100, roundUp10(v)) }
        v = mMcConf.getParamDouble("l_temp_motor_start");   if (v > 0) tempMotorStart = Math.ceil(v / 5) * 5
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

    Component.onCompleted: {
        negSpeed = VescIf.speedGaugeUseNegativeValues()
    }

    Connections {
        target: mCommands

        function onValuesReceived(values, mask) {
            if (!configRead) readConfig()

            var poles = mMcConf.getParamInt("si_motor_poles")
            var gear = mMcConf.getParamDouble("si_gear_ratio")
            var wheel = mMcConf.getParamDouble("si_wheel_diameter")
            var ms = (values.rpm / (poles / 2) / gear) * Math.PI * wheel / 60
            kmhSigned = ms * 3.6
            kmh = Math.abs(kmhSigned)
            if (kmh > speedPeakKm) speedPeakKm = kmh

            erpm = Math.abs(values.rpm)
            if (erpm > erpmMax) erpmMax = erpmRound(erpm * 1.1)

            ampsPhase = values.current_motor
            ampsBatt = values.current_in

            // Existing user-facing field-weakening gauge.
            // Negative Id is displayed as positive FW current.
            ampsFw = -values.id

            // Raw signed FOC telemetry.
            ampsId = values.id
            ampsIq = values.iq
            voltsD = values.vd
            voltsQ = values.vq
            voltsDQ = Math.sqrt(voltsD * voltsD + voltsQ * voltsQ)
            voltsRaw = values.v_in

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

            // Keep Id/Iq readable even if they exceed the configured phase-current range.
            var dqAbs = Math.max(Math.abs(ampsId), Math.abs(ampsIq))
            if (dqAbs > phaseLim) {
                maxPhase = roundUp20(dqAbs * 1.1)
                minPhase = -maxPhase
            }

            // low-pass the voltage so sag under load doesn't make the bar jump
            volts = volts === 0 ? values.v_in : volts * 0.9 + values.v_in * 0.1

            // estimated top speed: voltage / (sqrt(3) * 2 * pi * flux linkage), same math as the stock dashboard
            var fl = mMcConf.getParamDouble("foc_motor_flux_linkage")
            if (fl > 1e-4 && volts > 1) {
                var rpmMax = (volts * 60.0) / (Math.sqrt(3.0) * 2.0 * Math.PI * fl)
                if (rpmMax > erpmMax) erpmMax = erpmRound(rpmMax)
                var speedFact = ((poles / 2.0) * 60.0 * gear) / (wheel * Math.PI)
                if (speedFact > 1e-3) {
                    speedEstKm = 3.6 * rpmMax / speedFact
                    // dial range only grows, so it doesn't shrink when the voltage sags under load
                    if (speedEstKm > speedMaxKm) speedMaxKm = roundUp10(speedEstKm)
                }
            }

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

        function onValuesSetupReceived(values, mask) {
            fwLevel = values.battery_level

            // same sources as the stock page: odometer, trip (tachometer), up-time
            odoKm = values.odometer / 1000.0
            tripKm = values.tachometer_abs / 1000.0
            upMs = values.uptime_ms
            whNet = values.watt_hours - values.watt_hours_charged
        }
    }

    // dashboard page
    Item {
        id: dashPage
        anchors.fill: parent

        Item {
            id: gaugeArea
            x: portrait ? portraitMargin : areaMargin
            y: portrait ? topPad : areaMargin
            width: portrait ? mainItem.width - 2 * portraitMargin
                            : battBar.x - barGap - areaMargin
            height: portrait ? mainItem.height - topPad - statusH
                             : mainItem.height - 2 * areaMargin
            Repeater {
                model: gaugeCount
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
                    minAngle: portrait && col !== 1 ? outerMinAngle(index) : -defHalf
                    maxAngle: portrait && col !== 1 ? outerMaxAngle(index) : defHalf
                    minimumValue: d.lo
                    maximumValue: d.hi
                    labelStep: d.step !== undefined ? d.step : stepFor(d.lo, d.hi, d.n)
                    tickmarkScale: d.scale !== undefined ? d.scale : 1
                    tickmarkSuffix: d.suffix !== undefined ? d.suffix : ""
                    nibColor: d.c
                    value: d.v
                    unitText: d.unit
                    typeText: d.type
                }
            }

            // gear button, opens the settings dialog
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
                    onClicked: settingsDialog.open()
                }
            }
        }

        Rectangle {
            id: battBar
            property int segments: 10          // number of blocks
            property real segGap: Math.max(2, mainItem.ui * 0.006)   // space between blocks, 0 for a continuous bar

            width: portrait ? mainItem.width - 24 : Math.max(14, mainItem.ui * 0.045)
            height: portrait ? barH : mainItem.height - 2 * barMargin
            x: portrait ? 12 : textCol.x - textGap - width
            y: portrait ? textCol.y - barTextGap - barH : barMargin
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
                        property real t: battBar.segments > 1 ? 1 - level / (battBar.segments - 1) : 0   // 0 = light, 1 = dark
                        property real segPct: 100 / battBar.segments
                        property real frac: Math.max(0, Math.min(1, (battShown - level * segPct) / segPct))
                        width: portrait ? (parent.width - (battBar.segments - 1) * battBar.segGap) / battBar.segments
                                        : parent.width
                        height: portrait ? parent.height
                                         : (parent.height - (battBar.segments - 1) * battBar.segGap) / battBar.segments
                        radius: 0
                        color: "#2c2c2c"

                        // the colored part, fills from the bottom in landscape and from the left in portrait
                        Rectangle {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            width: portrait ? parent.width * frac : parent.width
                            height: portrait ? parent.height : parent.height * frac
                            color: Qt.rgba(0.247 - 0.204 * t, 0.722 - 0.177 * t, 0.937 - 0.215 * t, 1)
                        }
                    }
                }
            }
        }

        Item {
            id: textCol
            clip: true
            width: portrait ? mainItem.width : mainItem.width * 0.17
            height: portrait ? statusTextH : mainItem.height - 2 * textMargin
            x: portrait ? 0 : mainItem.width - width
            y: portrait ? mainItem.height - bottomPad - statusTextH : textMargin

            property color labelColor: "#ddd"
            property color valueColor: "#ddd"
            property color unitColor: "#ddd"
            property var labels: statusMode === 0 ? ["BATTERY", "VOLTAGE", "RANGE", "CONSUMPTION"]
                                                  : ["ODOMETER", "TRIP", "UP-TIME", "ENERGY"]
            property var units: statusMode === 0 ? ["%", "V", imperial ? "MI" : "KM", imperial ? "WH/MI" : "WH/KM"]
                                                 : [imperial ? "MI" : "KM", imperial ? "MI" : "KM", "", "WH"]

            function valueFor(i) {
                if (statusMode === 0) {
                    if (i === 0) return battPct.toFixed(0)
                    if (i === 1) return volts.toFixed(2)
                    if (i === 2) return range > 0 ? Math.min(range * distK, 999).toFixed(0) : "--"
                    return (whPerKm / distK).toFixed(0)
                }
                if (i === 0) return (odoKm * distK).toFixed(1)
                if (i === 1) return (tripKm * distK).toFixed(1)
                if (i === 2) return hms(upMs)
                return whNet.toFixed(0)
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

            // tap the status text to switch between the two sets
            MouseArea {
                anchors.fill: parent
                onClicked: statusMode = 1 - statusMode
            }
        }
    }

    // settings dialog, same style as the stock dashboard's
    Dialog {
        id: settingsDialog
        parent: dialogParent
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape
        standardButtons: Dialog.Ok | Dialog.Cancel

        // keep clear of the screen edges, mostly top and bottom
        property real vPad: Math.max(24, parent.height * 0.12)
        width: Math.min(parent.width - 24, 640)
        height: Math.min(implicitHeight, parent.height - 2 * vPad)
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        padding: 12

        Overlay.modal: Rectangle {
            color: "#AA000000"
        }

        // remember everything on open so Cancel can put it back
        onOpened: {
            negSpeed = VescIf.speedGaugeUseNegativeValues()
            odoField.text = (odoKm * distK).toFixed(2)

            mainItem.settingsSnap = {
                layoutIndex: mainItem.layoutIndex,
                mainGauge: mainItem.mainGauge,
                slotGauges: mainItem.slotGauges.slice(),
                orient: mainItem.orient,
                imperial: mainItem.imperial,
                tempF: mainItem.tempF,
                useFwLevel: mainItem.useFwLevel,
                negSpeed: mainItem.negSpeed,
                cells: mainItem.cells,
                packAh: mainItem.packAh
            }
        }

        onRejected: {
            var s = mainItem.settingsSnap
            if (!s) return
            mainItem.layoutIndex = s.layoutIndex
            mainItem.mainGauge = s.mainGauge
            mainItem.slotGauges = s.slotGauges
            mainItem.orient = s.orient
            mainItem.imperial = s.imperial
            mainItem.tempF = s.tempF
            mainItem.negSpeed = s.negSpeed
            mainItem.useFwLevel = s.useFwLevel
            mainItem.cells = s.cells
            mainItem.packAh = s.packAh
        }

        onAccepted: {
            VescIf.setSpeedGaugeUseNegativeValues(negSpeed)
        }

        ColumnLayout {
            anchors.fill: parent

            ScrollView {
                id: setScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    width: setScroll.availableWidth
                    spacing: 10

                    GroupBox {
                        title: qsTr("Layout: ") + (layoutIndex >= 0 ? presets[layoutIndex].name : "Custom")
                        Layout.fillWidth: true

                        ColumnLayout {
                            anchors.fill: parent

                            RowLayout {
                                Layout.fillWidth: true
                                Repeater {
                                    model: presets.length
                                    Button {
                                        Layout.fillWidth: true
                                        text: presets[index].name
                                        highlighted: layoutIndex === index
                                        onClicked: applyPreset(index)
                                    }
                                }
                            }

                            Repeater {
                                model: 7
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label {
                                        Layout.preferredWidth: 90
                                        text: index === 0 ? "Main gauge" : "Gauge " + index
                                    }
                                    Button { text: "<"; onClicked: cycleGauge(index, -1) }
                                    Label {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: nameOf(gaugeAt(index))
                                    }
                                    Button { text: ">"; onClicked: cycleGauge(index, 1) }
                                }
                            }

                            Label {
                                text: "Gauges 1 to 3 are the top row, 4 to 6 the bottom row"
                                opacity: 0.6
                            }
                        }
                    }

                    GroupBox {
                        title: qsTr("Display")
                        Layout.fillWidth: true

                        ColumnLayout {
                            anchors.fill: parent

                            RowLayout {
                                Layout.fillWidth: true
                                Button { Layout.fillWidth: true; text: "Auto"; highlighted: orient === 0; onClicked: orient = 0 }
                                Button { Layout.fillWidth: true; text: "Landscape"; highlighted: orient === 1; onClicked: orient = 1 }
                                Button { Layout.fillWidth: true; text: "Portrait"; highlighted: orient === 2; onClicked: orient = 2 }
                            }

                            Switch {
                                id: impSwitch
                                text: "Imperial speed (mph, mi)"
                                checked: imperial
                                onClicked: imperial = checked
                                Binding { target: impSwitch; property: "checked"; value: imperial }
                            }

                            Switch {
                                text: "Imperial temperature (°F)"
                                checked: tempF
                                onClicked: tempF = checked
                            }

                            Switch {
                                id: negSwitch
                                text: "Use negative speed"
                                checked: negSpeed
                                onClicked: negSpeed = checked
                                Binding { target: negSwitch; property: "checked"; value: negSpeed }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Info row"; Layout.preferredWidth: 90 }
                                Button { Layout.fillWidth: true; text: "Battery"; highlighted: statusMode === 0; onClicked: statusMode = 0 }
                                Button { Layout.fillWidth: true; text: "Trip"; highlighted: statusMode === 1; onClicked: statusMode = 1 }
                            }
                        }
                    }

                    GroupBox {
                        title: qsTr("Odometer")
                        Layout.fillWidth: true

                        RowLayout {
                            anchors.fill: parent

                            TextField {
                                id: odoField
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                            }
                            Label { text: imperial ? "mi" : "km" }
                            Button {
                                text: "Set"
                                onClicked: {
                                    // comma or dot both work, phones set to German use a comma
                                    var v = Number(odoField.text.replace(",", "."))
                                    if (!isNaN(v) && v >= 0 && v <= 20000000) {
                                        mCommands.setOdometer(Math.round(v / distK * 1000))
                                    }
                                }
                            }
                        }
                    }

                    GroupBox {
                        title: qsTr("Battery")
                        Layout.fillWidth: true

                        ColumnLayout {
                            anchors.fill: parent

                            Switch {
                                text: "Battery level from controller"
                                checked: useFwLevel
                                onClicked: useFwLevel = checked
                            }

                            Label {
                                text: "Cells and Ah are only used when the controller's level is off"
                                opacity: 0.6
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Cells in series"; Layout.fillWidth: true }
                                Button { text: "-"; onClicked: cells = Math.max(1, cells - 1) }
                                Label { text: cells; Layout.preferredWidth: 40; horizontalAlignment: Text.AlignHCenter }
                                Button { text: "+"; onClicked: cells = Math.min(40, cells + 1) }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Pack capacity (Ah)"; Layout.fillWidth: true }
                                Button { text: "-"; onClicked: packAh = Math.max(0.5, packAh - 0.5) }
                                Label { text: packAh.toFixed(1); Layout.preferredWidth: 40; horizontalAlignment: Text.AlignHCenter }
                                Button { text: "+"; onClicked: packAh = Math.min(500, packAh + 0.5) }
                            }
                        }
                    }

                    Label {
                        text: "Build " + version
                        opacity: 0.5
                    }
                }
            }
        }
    }
}