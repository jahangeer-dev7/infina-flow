import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: window

    // State reader from /run/user/1000/infina/state
    property string hudState: "idle"
    property real audioLevel: 0.0

    // Read state from file
    FileView {
        id: stateWatcher
        path: {
            const xdg = Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000";
            return xdg + "/infina/state";
        }
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const line = (text() || "").trim();
                if (line.startsWith("{")) {
                    const data = JSON.parse(line);
                    window.hudState = data.state || "idle";
                    window.audioLevel = data.level !== undefined ? data.level : 0.0;
                } else if (line.length > 0) {
                    window.hudState = line;
                }
            } catch (e) {
                window.hudState = (text() || "idle").trim();
            }
        }
    }

    // Backup polling timer ensures state updates reliably within 100ms
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: stateWatcher.reload()
    }

    // Visible when awake / active
    visible: hudState !== "disabled" && hudState !== "closed"

    // Positioned at the very bottom of the screen (small, compact line)
    anchors {
        bottom: true
    }

    // Sleek, compact dimensions (small line)
    implicitWidth: 260
    implicitHeight: 46
    color: "transparent"

    WlrLayershell.namespace: "infina-siri-wave"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Pointer events pass straight through so clicks reach windows behind
    mask: Region {
        intersection: Intersection.Subtract
        x: 0; y: 0
        width: window.width
        height: window.height
    }

    Item {
        id: siriWave
        anchors.fill: parent

        readonly property var params: {
            "idle":       { amp: 0.035, ampLevel: 0.0, freq: 1.6, freqLevel: 0.0, flow: 0.7, spread: 0.35, width: 1.5, wobble: 0.35, jitter: 0.0, line: 0.6, dim: 1.0, fill: 0.22, f0: 1.0, f1: 0.7, f2: 0.5, f3: 0.35 },
            "connecting": { amp: 0.26, ampLevel: 0.05, freq: 2.6, freqLevel: 0.0, flow: 1.4, spread: 0.0, width: 0.5, wobble: 0.1, jitter: 0.0, line: 0.45, dim: 0.92, fill: 0.28, f0: 1.0, f1: 0.3, f2: 0.18, f3: 0.1 },
            "listening":  { amp: 0.08, ampLevel: 0.55, freq: 2.6, freqLevel: 1.6, flow: 2.4, spread: 0.55, width: 1.0, wobble: 0.3, jitter: 0.0, line: 0.35, dim: 1.0, fill: 0.26, f0: 1.0, f1: 0.8, f2: 0.65, f3: 0.5 },
            "thinking":   { amp: 0.22, ampLevel: 0.05, freq: 3.4, freqLevel: 0.0, flow: 2.0, spread: 0.0, width: 0.5, wobble: 0.15, jitter: 0.0, line: 0.4, dim: 1.0, fill: 0.28, f0: 1.0, f1: 0.85, f2: 0.7, f3: 0.55 },
            "speaking":   { amp: 0.08, ampLevel: 0.6, freq: 2.8, freqLevel: 3.2, flow: 3.4, spread: 1.0, width: 1.05, wobble: 0.3, jitter: 0.0, line: 0.25, dim: 1.0, fill: 0.3, f0: 1.0, f1: 0.9, f2: 0.8, f3: 0.7 },
            "error":      { amp: 0.13, ampLevel: 0.0, freq: 7.5, freqLevel: 0.0, flow: 4.0, spread: 0.2, width: 0.55, wobble: 0.0, jitter: 0.8, line: 0.45, dim: 1.0, fill: 0.3, f0: 1.0, f1: 0.8, f2: 0.6, f3: 0.45 },
            "disabled":   { amp: 0.006, ampLevel: 0.0, freq: 1.2, freqLevel: 0.0, flow: 0.2, spread: 0.2, width: 1.8, wobble: 0.0, jitter: 0.0, line: 0.35, dim: 0.45, fill: 0.15, f0: 1.0, f1: 0.3, f2: 0.2, f3: 0.1 }
        }

        readonly property var baseCenter: [-0.35, 0.4, 0.05, -0.7]
        readonly property var freqMul: [1.0, 1.3, 0.75, 1.55]
        readonly property var flowMul: [1.0, 1.2, 0.85, 1.4]
        readonly property var wobbleRate: [1.3, 1.7, 2.1, 1.1]
        readonly property var seed: [0.3, 2.1, 4.2, 5.4]

        property real phase: 0.0
        property real smoothedLevel: 0.0

        Timer {
            interval: 16
            running: window.visible
            repeat: true
            onTriggered: {
                siriWave.phase += 0.035
                siriWave.smoothedLevel += (window.audioLevel - siriWave.smoothedLevel) * 0.25
                canvas.requestPaint()
            }
        }

        Canvas {
            id: canvas
            anchors.fill: parent
            renderTarget: Canvas.FramebufferObject

            onPaint: {
                var ctx = getContext("2d");
                var w = width;
                var h = height;
                ctx.reset();
                ctx.clearRect(0, 0, w, h);

                var stateKey = window.hudState in siriWave.params ? window.hudState : "idle";
                var p = siriWave.params[stateKey];
                var level = siriWave.smoothedLevel;

                var SAMPLES = 70;
                var CURVES = 4;
                var cy = h / 2;
                var pad = 14;
                var halfH = h * 0.40;
                var ph = siriWave.phase;

                // Center glowing gradient line
                var baseGrad = ctx.createLinearGradient(pad, 0, w - pad, 0);
                baseGrad.addColorStop(0.0, "rgba(139, 92, 246, 0.0)");
                baseGrad.addColorStop(0.2, "rgba(139, 92, 246, 0.5)");
                baseGrad.addColorStop(0.5, "rgba(217, 70, 239, 0.95)");
                baseGrad.addColorStop(0.8, "rgba(139, 92, 246, 0.5)");
                baseGrad.addColorStop(1.0, "rgba(139, 92, 246, 0.0)");

                ctx.fillStyle = baseGrad;
                ctx.fillRect(pad, cy - 1, w - pad * 2, 1.5);

                var colors = [
                    "rgba(139, 92, 246, ", // #8b5cf6 violet
                    "rgba(217, 70, 239, ", // #d946ef fuchsia
                    "rgba(56, 189, 248, ",  // #38bdf8 cyan
                    "rgba(244, 63, 94, "   // #f43f5e rose
                ];

                var factors = [p.f0, p.f1, p.f2, p.f3];
                var baseAmp = (p.amp + p.ampLevel * level) * halfH;

                ctx.globalCompositeOperation = "lighter";

                for (var k = CURVES - 1; k >= 0; k--) {
                    var wob = 1.0 - p.wobble * (0.5 + 0.5 * Math.sin(ph * siriWave.wobbleRate[k] + siriWave.seed[k]));
                    var amp = baseAmp * factors[k] * wob;
                    if (amp < 0.6) amp = 0.6;

                    var fk = (p.freq + p.freqLevel * level) * siriWave.freqMul[k];
                    var flow = p.flow * siriWave.flowMul[k];
                    var curvePhase = ph * flow + siriWave.seed[k];
                    var center = p.spread * siriWave.baseCenter[k];

                    ctx.beginPath();
                    ctx.moveTo(pad, cy);

                    var xs = [];
                    var ys = [];

                    for (var j = 0; j < SAMPLES; j++) {
                        var u = j / (SAMPLES - 1);
                        var x = pad + u * (w - pad * 2);
                        var xn = (u * 2 - 1) * 2.0;
                        var env = Math.exp(-Math.pow((xn - center) / p.width, 2));
                        var yOffset = amp * env * Math.sin(fk * xn - curvePhase);
                        xs.push(x);
                        ys.push(yOffset);
                        ctx.lineTo(x, cy - yOffset);
                    }

                    for (var j = SAMPLES - 1; j >= 0; j--) {
                        ctx.lineTo(xs[j], cy + ys[j]);
                    }
                    ctx.closePath();

                    // Fill
                    ctx.fillStyle = colors[k] + (p.fill * 0.7).toFixed(2) + ")";
                    ctx.fill();

                    // Stroke
                    ctx.strokeStyle = colors[k] + (p.line * 0.95).toFixed(2) + ")";
                    ctx.lineWidth = 1.2;
                    ctx.stroke();
                }
                ctx.globalCompositeOperation = "source-over";
            }
        }
    }
}
