import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Last good snapshot from `claude-usage-estimator get --json`: the pooled Anthropic
    // provider, or nothing before the first good poll:
    //   [{ provider: "anthropic", label: "Claude", members: [account], windows: { "5h": win, "7d": win },
    //      block, verdict }]
    // win: { kind, state, used, start, resetsAt, idle, forecast, verdict, runsOut,
    //        outAt, outEarly, outLate, out, of }, times in unix ms, fractions in 0..1; `used` is
    //        the mean over the pool, `out` of the `of` accounts are out of this window now.
    // block: the window that makes the pool unusable soonest (exhausted now, else the
    //        earliest median run-out): { from, until, kind, exhausted } or null.
    property var pools: []
    // Daemon health carried by the snapshot.
    property double generatedAt: 0
    property string pollError: ""
    property string historyError: ""
    // Stored samples of the last week, keyed "account|limit" -> [[t, used], …] sorted by t.
    // Only fetched while the popup is open; the charts fall back to a straight line.
    property var samples: ({})
    property string lastError: ""
    property bool loading: false
    property bool everLoaded: false
    // Bumped by the countdown timer so every time-relative binding re-evaluates.
    property double nowMs: Date.now()

    readonly property string serverArg: {
        const s = Plasmoid.configuration.server.trim();
        return s === "" ? "" : " --server '" + s.replace(/'/g, "'\\''") + "'";
    }
    readonly property string estimatesCommand: Plasmoid.configuration.estimator + " get --json" + serverArg
    readonly property string samplesCommand: Plasmoid.configuration.estimator + " get samples --json" + serverArg

    readonly property double minuteMs: 60000
    readonly property double hourMs: 3600000
    readonly property double dayMs: 86400000
    /** The daemon looks stuck past this snapshot age (cue_core STALE_AFTER_MS). */
    readonly property double staleAfterMs: 3 * minuteMs
    readonly property bool stale: generatedAt > 0 && nowMs - generatedAt > staleAfterMs
    readonly property bool unhealthy: stale || pollError !== "" || historyError !== ""

    /** Bounds for the in-panel width, in px. Mirrored by the config spin box. */
    readonly property int minPanelWidth: 48
    readonly property int maxPanelWidth: 600
    /** >= 0 only while a resize grip is being dragged; overrides the stored width live so the
     *  drag stays smooth without writing config on every mouse move. */
    property int dragWidth: -1
    readonly property int effectiveWidth: Math.max(minPanelWidth, Math.min(maxPanelWidth,
        dragWidth >= 0 ? dragWidth : Plasmoid.configuration.panelWidth))

    // Verdict colours from the desktop's Monokai Pro Spectrum palette. Fixed rather than
    // theme roles: the stylix scheme maps neutralTextColor to cyan.
    readonly property var verdictColors: ({ "ok": "#7bd88f", "warn": "#fce566", "bad": "#fc618d" })
    readonly property color trackColor: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                                Kirigami.Theme.textColor.b, 0.17)
    readonly property color availableColor: Qt.rgba(0.482, 0.847, 0.561, 0.32)
    readonly property color ruleColor: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                               Kirigami.Theme.textColor.b, 0.1)
    // Secondary text. Opaque so it also works in Canvas and StyledText, and derived from the
    // text colour because the stylix scheme sets inactive/disabled text equal to normal text.
    readonly property color dimTextColor: Qt.tint(Kirigami.Theme.backgroundColor,
                                                  Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                                          Kirigami.Theme.textColor.b, 0.55))
    readonly property var weekdays: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    function verdictColor(v) {
        return verdictColors[v] || verdictColors.ok;
    }

    function clamp01(x) {
        return Math.max(0, Math.min(1, x));
    }

    function pct(f) {
        return Math.round(f * 100) + "%";
    }

    function pad2(n) {
        return n < 10 ? "0" + n : String(n);
    }

    function hm(t) {
        const d = new Date(t);
        return pad2(d.getHours()) + ":" + pad2(d.getMinutes());
    }

    function dayDelta(t, now) {
        const a = new Date(t), b = new Date(now);
        const da = new Date(a.getFullYear(), a.getMonth(), a.getDate()).getTime();
        const db = new Date(b.getFullYear(), b.getMonth(), b.getDate()).getTime();
        return Math.round((da - db) / dayMs);
    }

    /** "17:15" today, else "Wed 16:00". */
    function shortTime(t, now) {
        return dayDelta(t, now) === 0 ? hm(t) : weekdays[new Date(t).getDay()] + " " + hm(t);
    }

    /** "17:15", "tomorrow 16:00" or "Wed 16:00". */
    function longTime(t, now) {
        const dd = dayDelta(t, now);
        if (dd === 0)
            return hm(t);
        if (dd === 1)
            return "tomorrow " + hm(t);
        return weekdays[new Date(t).getDay()] + " " + hm(t);
    }

    /** "2h 18m", "3d 2h", "45m", "now". */
    function duration(ms) {
        let m = Math.round(ms / minuteMs);
        if (m < 1)
            return "now";
        const d = Math.floor(m / 1440);
        m -= d * 1440;
        const h = Math.floor(m / 60);
        m -= h * 60;
        if (d > 0)
            return d + "d " + h + "h";
        if (h > 0)
            return h + "h " + pad2(m) + "m";
        return m + "m";
    }

    function windowName(kind) {
        return kind === "5h" ? "5 hours" : "7 days";
    }

    /** Rounds a run-out time to what the forecast resolves: 5 min (5h) or 1 h (7d). */
    function roundRunsOut(t, windowMs) {
        const step = windowMs > 6 * hourMs ? hourMs : 5 * minuteMs;
        return Math.floor((t + step / 2) / step) * step;
    }

    function present(v) {
        return v !== undefined && v !== null;
    }

    function normalizeWindow(e) {
        const f = e.forecast || null;
        const resetsAt = present(e.resetsAt) ? e.resetsAt : null;
        const start = present(e.start) ? e.start : (resetsAt !== null ? resetsAt - e.windowMs : null);
        const runsOut = e.state === "active" && f !== null && present(f.emptyAt.p50);
        let verdict = "ok";
        if (e.state === "exhausted" || runsOut)
            verdict = "bad";
        else if (e.state === "active" && f !== null && f.pEmpty >= 0.25)
            verdict = "warn";
        const r = t => present(t) ? roundRunsOut(t, e.windowMs) : null;
        return {
            "kind": e.limit === "anthropic:5h" ? "5h" : "7d",
            "limit": e.limit,
            "state": e.state,
            "used": e.used,
            "start": start,
            "resetsAt": resetsAt,
            "idle": !!e.idle,
            "forecast": f,
            "verdict": verdict,
            "runsOut": runsOut,
            "outAt": runsOut ? r(f.emptyAt.p50) : null,
            "outEarly": f ? r(f.emptyAt.p10) : null,
            "outLate": f ? r(f.emptyAt.p90) : null,
            "out": e.exhausted || 0,
            "of": e.accounts || 1
        };
    }

    /** Fraction of the window elapsed at `now`, or -1 outside an active window. */
    function elapsed(win, now) {
        if (!win || win.state !== "active" || win.start === null || win.resetsAt === null)
            return -1;
        return clamp01((now - win.start) / (win.resetsAt - win.start));
    }

    /** Predicted unavailability of one window: [{ early, from, until, kind }]. A run-out
     *  fades in from its 10th to its 50th percentile; a likely (>= 25 %) one is shown
     *  half-strength from the earliest plausible run-out. */
    function windowBlocks(win, now) {
        if (!win || win.resetsAt === null)
            return [];
        if (win.state === "exhausted")
            return [{ "early": now, "from": now, "until": win.resetsAt, "kind": "bad" }];
        if (win.runsOut)
            return [{ "early": win.outEarly !== null ? win.outEarly : win.outAt, "from": win.outAt,
                      "until": win.resetsAt, "kind": "bad" }];
        if (win.verdict === "warn" && win.outEarly !== null)
            return [{ "early": win.outEarly, "from": win.outEarly, "until": win.resetsAt, "kind": "warn" }];
        return [];
    }

    function poolBlocks(pool, now) {
        return windowBlocks(pool.windows["5h"], now).concat(windowBlocks(pool.windows["7d"], now));
    }

    /** The panel's countdown slot: null while the pool is on track. */
    function countdown(pool, now) {
        const b = pool.block;
        if (b !== null && b.exhausted)
            return { "back": true, "value": duration(b.until - now), "window": b.kind, "verdict": "bad" };
        if (b !== null)
            return { "back": false, "value": duration(b.from - now), "window": b.kind, "verdict": "bad" };
        if (pool.verdict === "warn") {
            const ws = [pool.windows["5h"], pool.windows["7d"]]
                .filter(w => w && w.verdict === "warn")
                .sort((x, y) => y.forecast.pEmpty - x.forecast.pEmpty);
            return { "back": false, "value": pct(ws[0].forecast.pEmpty) + " risk", "window": ws[0].kind, "verdict": "warn" };
        }
        return null;
    }

    /** The popup's per-pool headline: [text, verdict]. */
    function poolStatus(pool, now) {
        const b = pool.block;
        if (b !== null && b.exhausted)
            return ["Out until " + longTime(b.until, now), "bad"];
        if (b !== null)
            return ["Runs out " + longTime(b.from, now), "bad"];
        if (pool.verdict === "warn")
            return ["Might run out", "warn"];
        return ["On track", "ok"];
    }

    /** [text, verdict] over the union of the pools' predicted unavailable spans. */
    function availabilityHeadline(pools, now) {
        const bad = [];
        for (const p of pools)
            for (const b of poolBlocks(p, now))
                if (b.kind === "bad" && b.until > Math.max(now, b.from))
                    bad.push({ "from": Math.max(now, b.from), "until": b.until });
        bad.sort((p, q) => p.from - q.from);
        const spans = [];
        for (const b of bad) {
            if (spans.length > 0 && b.from <= spans[spans.length - 1].until)
                spans[spans.length - 1].until = Math.max(spans[spans.length - 1].until, b.until);
            else
                spans.push(b);
        }
        if (spans.length === 0)
            return ["Available all week", "ok"];
        return ["Unavailable " + spans.map(b => shortTime(b.from, now) + "–" + shortTime(b.until, now)).join(" and "), "bad"];
    }

    /** Pooled usage history of one limit, [[t, used], …]: the members' sample series merged by
     *  time, each member holding its latest `used` (0 before its first sample), averaged over
     *  the window's `of` accounts. */
    function poolPoints(pool, limit) {
        const win = pool.windows[limit === "anthropic:5h" ? "5h" : "7d"];
        if (!win)
            return [];
        const events = [];
        pool.members.forEach((m, i) => {
            for (const s of samples[m + "|" + limit] || [])
                events.push([s[0], i, s[1]]);
        });
        events.sort((p, q) => p[0] - q[0]);
        const latest = pool.members.map(() => 0);
        let sum = 0;
        const out = [];
        for (const e of events) {
            sum += e[2] - latest[e[1]];
            latest[e[1]] = e[2];
            const pt = [e[0], sum / win.of];
            if (out.length > 0 && out[out.length - 1][0] === e[0])
                out[out.length - 1] = pt;
            else
                out.push(pt);
        }
        return out;
    }

    /** Position on the popup timeline, 0..1: the next 24 h take the left half, the
     *  following six days the right half. */
    function axisFraction(t, now) {
        const dt = Math.max(0, t - now);
        if (dt <= dayMs)
            return 0.5 * dt / dayMs;
        return Math.min(1, 0.5 + 0.5 * (dt - dayMs) / (6 * dayMs));
    }

    /** Timeline ticks: [{ t, label }] for now, 6-hourly marks in the first day (kept clear
     *  of "now" by `minGapPx`) and midnights of the following days. */
    function timelineTicks(now, laneWidth, minGapPx) {
        const n = new Date(now);
        const ticks = [{ "t": now, "label": "now" }];
        for (let h = Math.ceil((n.getHours() + 1) / 6) * 6; h <= n.getHours() + 24; h += 6) {
            const t = new Date(n.getFullYear(), n.getMonth(), n.getDate(), h).getTime();
            if (t - now <= dayMs && axisFraction(t, now) * laneWidth > minGapPx)
                ticks.push({ "t": t, "label": hm(t) });
        }
        for (let d = 2; d <= 7; d++) {
            const t = new Date(n.getFullYear(), n.getMonth(), n.getDate() + d).getTime();
            if (t - now > dayMs + 3 * hourMs && t - now <= 7 * dayMs)
                ticks.push({ "t": t, "label": weekdays[new Date(t).getDay()] });
        }
        return ticks;
    }

    function refresh() {
        loading = true;
        if (exec.connectedSources.indexOf(root.estimatesCommand) === -1)
            exec.connectSource(root.estimatesCommand);
    }

    function refreshSamples() {
        if (exec.connectedSources.indexOf(root.samplesCommand) === -1)
            exec.connectSource(root.samplesCommand);
    }

    function commandError(exitCode, stderr) {
        return (stderr && stderr.trim().length > 0) ? stderr.trim().split("\n")[0] : ("command exited " + exitCode);
    }

    function handleEstimates(exitCode, stdout, stderr) {
        loading = false;
        everLoaded = true;
        if (exitCode !== 0) {
            lastError = commandError(exitCode, stderr);
            return;
        }
        let snap;
        try {
            snap = JSON.parse(stdout);
        } catch (e) {
            lastError = "parse error: " + e.message;
            return;
        }
        const p = (snap && snap.providers || []).find(x => x.provider === "anthropic");
        const now = snap.generatedAt || Date.now();
        let out = [];
        if (p) {
            const pool = {
                "provider": "anthropic",
                "label": "Claude",
                "members": (p.accounts || []).map(a => a.account),
                "windows": { "5h": null, "7d": null }
            };
            for (const e of p.windows || []) {
                if (e.limit !== "anthropic:5h" && e.limit !== "anthropic:7d")
                    continue;
                const w = normalizeWindow(e);
                pool.windows[w.kind] = w;
            }
            const ws = [pool.windows["5h"], pool.windows["7d"]].filter(w => w !== null);
            const ex = ws.find(w => w.state === "exhausted" && w.resetsAt !== null);
            const outs = ws.filter(w => w.runsOut).sort((x, y) => x.outAt - y.outAt);
            if (ex)
                pool.block = { "from": now, "until": ex.resetsAt, "kind": ex.kind, "exhausted": true };
            else if (outs.length > 0)
                pool.block = { "from": outs[0].outAt, "until": outs[0].resetsAt, "kind": outs[0].kind, "exhausted": false };
            else
                pool.block = null;
            pool.verdict = ws.some(w => w.verdict === "bad") ? "bad" : (ws.some(w => w.verdict === "warn") ? "warn" : "ok");
            out = [pool];
        }
        pools = out;
        generatedAt = snap.generatedAt || 0;
        pollError = snap.pollError || "";
        historyError = snap.historyError || "";
        lastError = "";
        nowMs = Date.now();
    }

    function handleSamples(exitCode, stdout, stderr) {
        if (exitCode !== 0) {
            lastError = commandError(exitCode, stderr);
            return;
        }
        // Current windows start at most 7 d ago; keep a little slack for the window start.
        const since = Date.now() - 7 * dayMs - hourMs;
        const out = ({});
        const lines = stdout.split("\n");
        for (const line of lines) {
            if (line.length === 0)
                continue;
            let s;
            try {
                s = JSON.parse(line);
            } catch (e) {
                continue;
            }
            if (s.t < since)
                continue;
            const key = s.account + "|" + s.limit;
            if (out[key] === undefined)
                out[key] = [];
            out[key].push([s.t, s.used]);
        }
        for (const key in out)
            out[key].sort((p, q) => p[0] - q[0]);
        samples = out;
    }

    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            exec.disconnectSource(source);
            if (source === root.samplesCommand)
                root.handleSamples(data["exit code"], data.stdout, data.stderr);
            else
                root.handleEstimates(data["exit code"], data.stdout, data.stderr);
        }
    }

    // Poll the daemon. triggeredOnStart gives an immediate first read.
    Timer {
        interval: Math.max(15, Plasmoid.configuration.pollIntervalSeconds) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Refresh only the countdowns and the stale check between polls.
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.nowMs = Date.now()
    }

    onExpandedChanged: {
        if (root.expanded) {
            refresh();
            refreshSamples();
        }
    }

    toolTipMainText: "Claude usage"
    toolTipTextFormat: Text.StyledText
    toolTipSubText: {
        if (pools.length === 0)
            return lastError !== "" ? lastError : "No estimates from claude-usage-estimator";
        const now = nowMs;
        const span = (v, s) => "<font color=\"" + verdictColor(v) + "\">" + s + "</font>";
        const dim = s => "<font color=\"" + dimTextColor + "\">" + s + "</font>";
        const lines = [];
        if (unhealthy)
            lines.push(span("warn", stale ? "Estimates are " + duration(now - generatedAt) + " old" : "Daemon poll failed"));
        for (const p of pools) {
            for (const kind of ["5h", "7d"]) {
                const w = p.windows[kind];
                if (!w)
                    continue;
                let tail;
                if (w.state === "exhausted")
                    tail = span("bad", "exhausted, back " + shortTime(w.resetsAt, now));
                else if (w.runsOut)
                    tail = span("bad", "out " + shortTime(w.outAt, now)) + dim(", back " + shortTime(w.resetsAt, now));
                else if (w.forecast)
                    tail = (w.verdict === "warn"
                            ? span("warn", "≈" + pct(Math.min(1, w.forecast.atReset.p50)) + " at reset, " + pct(w.forecast.pEmpty) + " risk")
                            : "≈" + pct(Math.min(1, w.forecast.atReset.p50)) + " at reset")
                        + dim(", resets " + shortTime(w.resetsAt, now));
                else if (w.state === "not_started")
                    tail = dim("not started");
                else
                    tail = dim("no data");
                const outs = w.of > 1 ? dim(", " + w.out + "/" + w.of + " out") : "";
                lines.push(kind + " " + pct(w.used) + ", " + tail + outs);
            }
        }
        return lines.join("<br>");
    }

    // Usage bar on a 0..100 % axis: solid = used, lighter = median projection at reset,
    // faint = up to the 90th percentile; the tick marks the elapsed share of the window, so
    // usage left of it is under a steady pace.
    component ProjectionBar: Item {
        id: bar
        property var win: null
        property bool dimmed: false
        readonly property var forecast: win && win.state === "active" ? win.forecast : null
        readonly property color tone: (dimmed || !win) ? root.dimTextColor : root.verdictColor(win.verdict)
        readonly property real tick: root.elapsed(win, root.nowMs)

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.trackColor
        }
        Rectangle {
            visible: bar.forecast !== null
            width: bar.width * root.clamp01(bar.forecast ? bar.forecast.atReset.p90 : 0)
            height: parent.height
            radius: height / 2
            color: bar.tone
            opacity: 0.22
        }
        Rectangle {
            visible: bar.forecast !== null
            width: bar.width * root.clamp01(bar.forecast ? bar.forecast.atReset.p50 : 0)
            height: parent.height
            radius: height / 2
            color: bar.tone
            opacity: 0.3
        }
        Rectangle {
            visible: bar.win !== null
            width: bar.width * root.clamp01(bar.win ? bar.win.used : 0)
            height: parent.height
            radius: height / 2
            color: bar.tone
            opacity: bar.win && bar.win.idle ? 0.75 : 1
        }
        Rectangle {
            visible: bar.tick >= 0
            x: bar.width * bar.tick - width / 2
            y: -2
            width: 1.5
            height: parent.height + 4
            color: Kirigami.Theme.textColor
            opacity: 0.9
        }
    }

    // Availability lane on the popup timeline: greenish when usable, red from the median
    // run-out (faded in from the 10th percentile) to the reset.
    component Lane: Item {
        id: lane
        property var blocks: []
        property string annotation: ""
        property real annotationX: -1

        Rectangle {
            anchors.fill: parent
            radius: 3
            color: root.availableColor
        }
        Repeater {
            model: lane.blocks
            delegate: Item {
                id: blk
                required property var modelData
                readonly property real x0: lane.width * root.axisFraction(Math.max(root.nowMs, modelData.early), root.nowMs)
                readonly property real x1: lane.width * root.axisFraction(Math.max(root.nowMs, modelData.from), root.nowMs)
                readonly property real x2: lane.width * root.axisFraction(modelData.until, root.nowMs)
                readonly property color tone: root.verdictColor(modelData.kind)
                anchors.fill: parent
                visible: x2 > 0

                Rectangle {
                    x: blk.x0
                    width: Math.max(0, blk.x1 - blk.x0)
                    height: parent.height
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.rgba(blk.tone.r, blk.tone.g, blk.tone.b, 0) }
                        GradientStop { position: 1; color: blk.tone }
                    }
                }
                Rectangle {
                    x: blk.x1
                    width: Math.max(0, blk.x2 - blk.x1)
                    height: parent.height
                    radius: blk.x2 >= lane.width - 0.5 ? 3 : 0
                    color: blk.tone
                    opacity: blk.modelData.kind === "warn" ? 0.55 : 1
                }
            }
        }
        PlasmaComponents3.Label {
            visible: lane.annotation !== ""
            x: lane.annotationX + Kirigami.Units.smallSpacing
            anchors.verticalCenter: parent.verticalCenter
            text: lane.annotation
            font.pixelSize: lane.height - 3
            font.weight: Font.DemiBold
            color: Kirigami.Theme.backgroundColor
        }
    }

    // Burn-up chart of one window: x = window start → reset, y = 0 → 100 %. Usage so far as
    // a step curve (straight line until samples load), then the forecast fan to the reset
    // (10th–90th percentile), the dashed median and a dot where the median hits 100 %.
    component BurnChart: Canvas {
        id: chart
        property var win: null
        property var points: []
        property bool dimmed: false
        readonly property double now: root.nowMs

        onWinChanged: requestPaint()
        onPointsChanged: requestPaint()
        onDimmedChanged: requestPaint()
        onNowChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const w = width, h = height;
            const fg = Kirigami.Theme.textColor.toString();
            ctx.globalAlpha = 0.06;
            ctx.fillStyle = fg;
            ctx.beginPath();
            ctx.roundedRect(0, 0, w, h, 3, 3);
            ctx.fill();
            ctx.globalAlpha = 1;
            const win = chart.win;
            if (!win || win.start === null || win.resetsAt === null || w <= 0 || h <= 0) {
                ctx.strokeStyle = fg;
                ctx.globalAlpha = 0.25;
                ctx.setLineDash([2, 3]);
                ctx.beginPath();
                ctx.moveTo(3, h - 0.5);
                ctx.lineTo(w - 3, h - 0.5);
                ctx.stroke();
                return;
            }
            const now = Math.min(chart.now, win.resetsAt);
            const c = chart.dimmed ? root.dimTextColor.toString() : root.verdictColor(win.verdict);
            const tx = t => w * (t - win.start) / (win.resetsAt - win.start);
            const uy = u => h - (h - 1.5) * Math.min(1, u);

            ctx.save();
            ctx.beginPath();
            ctx.rect(0, 0, w, h);
            ctx.clip();

            // 100 % ceiling.
            ctx.strokeStyle = fg;
            ctx.globalAlpha = 0.25;
            ctx.lineWidth = 1;
            ctx.setLineDash([2, 3]);
            ctx.beginPath();
            ctx.moveTo(0, 1);
            ctx.lineTo(w, 1);
            ctx.stroke();
            ctx.setLineDash([]);

            // History.
            const pts = chart.points.filter(p => p[0] >= win.start && p[0] <= now);
            const path = () => {
                ctx.moveTo(tx(win.start), uy(0));
                if (pts.length === 0) {
                    ctx.lineTo(tx(now), uy(win.used));
                    return;
                }
                let prev = 0;
                for (const p of pts) {
                    ctx.lineTo(tx(p[0]), uy(prev));
                    ctx.lineTo(tx(p[0]), uy(p[1]));
                    prev = p[1];
                }
                ctx.lineTo(tx(now), uy(prev));
                ctx.lineTo(tx(now), uy(win.used));
            };
            ctx.fillStyle = c;
            ctx.globalAlpha = 0.28;
            ctx.beginPath();
            path();
            ctx.lineTo(tx(now), uy(0));
            ctx.closePath();
            ctx.fill();
            ctx.strokeStyle = c;
            ctx.globalAlpha = 1;
            ctx.lineWidth = 1.4;
            ctx.beginPath();
            path();
            ctx.stroke();

            // Forecast.
            const f = win.state === "active" ? win.forecast : null;
            if (f) {
                const edge = (outT, atReset) => root.present(outT)
                    ? [[tx(outT), uy(1)], [tx(win.resetsAt), uy(1)]]
                    : [[tx(win.resetsAt), uy(atReset)]];
                const upper = edge(f.emptyAt.p10, f.atReset.p90);
                const lower = edge(f.emptyAt.p90, f.atReset.p10).reverse();
                ctx.globalAlpha = 0.2;
                ctx.beginPath();
                ctx.moveTo(tx(now), uy(win.used));
                for (const p of upper.concat(lower))
                    ctx.lineTo(p[0], p[1]);
                ctx.closePath();
                ctx.fill();
                ctx.globalAlpha = 1;
                ctx.lineWidth = 1.3;
                ctx.setLineDash([3, 2]);
                ctx.beginPath();
                ctx.moveTo(tx(now), uy(win.used));
                for (const p of edge(f.emptyAt.p50, f.atReset.p50))
                    ctx.lineTo(p[0], p[1]);
                ctx.stroke();
                ctx.setLineDash([]);
            }
            ctx.restore();

            // Now marker.
            ctx.globalAlpha = 0.55;
            ctx.fillStyle = fg;
            ctx.fillRect(tx(now) - 0.5, 0, 1, h);
            ctx.globalAlpha = 1;

            if (win.runsOut) {
                const dx = tx(win.forecast.emptyAt.p50);
                ctx.fillStyle = root.verdictColors.bad;
                ctx.strokeStyle = Kirigami.Theme.backgroundColor.toString();
                ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.arc(dx, uy(1) + 1.5, 3.5, 0, 2 * Math.PI);
                ctx.fill();
                ctx.stroke();
                const px = Math.round(Kirigami.Theme.smallFont.pixelSize > 0
                    ? Kirigami.Theme.smallFont.pixelSize * 0.9
                    : Kirigami.Theme.smallFont.pointSize * 1.2);
                ctx.font = "bold " + px + "px \"" + Kirigami.Theme.smallFont.family + "\"";
                const label = root.hm(win.outAt);
                const right = dx + ctx.measureText(label).width + 8 < w;
                ctx.textAlign = right ? "left" : "right";
                ctx.textBaseline = "top";
                ctx.fillText(label, right ? dx + 6 : dx - 6, 4);
            }
        }
    }

    // One window in the popup: headline numbers, chart, then start / risk / reset.
    component ChartCell: ColumnLayout {
        id: cell
        property var win: null
        property var points: []
        spacing: 2

        readonly property var forecast: win && win.state === "active" ? win.forecast : null
        readonly property string rightText: {
            if (!win)
                return "";
            if (win.runsOut)
                return "out " + root.shortTime(win.outAt, root.nowMs);
            if (win.state === "exhausted")
                return "back " + root.shortTime(win.resetsAt, root.nowMs);
            if (forecast)
                return "≈" + root.pct(Math.min(1, forecast.atReset.p50)) + " at reset";
            if (win.state === "not_started")
                return "not started";
            if (win.state === "expired")
                return "waiting for data";
            return "no data yet";
        }
        readonly property bool alarm: win !== null && (win.runsOut || win.state === "exhausted")

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents3.Label {
                text: cell.win ? root.pct(cell.win.used) : "–"
                font.bold: true
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
                color: cell.win ? root.verdictColor(cell.win.verdict) : root.dimTextColor
            }
            PlasmaComponents3.Label {
                text: cell.win ? root.windowName(cell.win.kind) : ""
                font: Kirigami.Theme.smallFont
                color: root.dimTextColor
            }
            // Elide rather than widen the cell: the two cells share the popup width.
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: cell.rightText
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                font.weight: cell.alarm ? Font.DemiBold : Font.Normal
                color: cell.alarm ? root.verdictColors.bad : Kirigami.Theme.textColor
            }
        }
        BurnChart {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2.2
            win: cell.win
            points: cell.points
            dimmed: root.stale
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents3.Label {
                text: cell.win && cell.win.start !== null ? root.shortTime(cell.win.start, root.nowMs) : ""
                font: Kirigami.Theme.smallFont
                color: root.dimTextColor
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: {
                    const parts = [];
                    if (cell.win && cell.win.of > 1)
                        parts.push(cell.win.out + "/" + cell.win.of + " out");
                    if (cell.forecast)
                        parts.push(root.pct(cell.forecast.pEmpty) + " risk, " + (cell.win.idle ? "idle" : cell.forecast.pace.toFixed(1) + "× pace"));
                    return parts.join(", ");
                }
                font: Kirigami.Theme.smallFont
                color: root.dimTextColor
            }
            PlasmaComponents3.Label {
                text: cell.win && cell.win.resetsAt !== null ? root.shortTime(cell.win.resetsAt, root.nowMs) : ""
                font: Kirigami.Theme.smallFont
                color: root.dimTextColor
            }
        }
    }

    compactRepresentation: MouseArea {
        id: compactRoot
        // One entry per pool; a single null column keeps the placeholder bars visible
        // before the first successful poll.
        readonly property var columns: root.pools.length > 0 ? root.pools : [null]

        // The configured width wins: columns share whatever room it gives them, and the
        // user widens the widget by dragging.
        Layout.minimumWidth: root.effectiveWidth
        Layout.preferredWidth: root.effectiveWidth
        onClicked: root.expanded = !root.expanded

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.smallSpacing
            anchors.rightMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.largeSpacing * 2

            Repeater {
                model: compactRoot.columns
                delegate: RowLayout {
                    id: poolColumn
                    required property var modelData
                    readonly property var pool: modelData
                    readonly property var cd: pool ? root.countdown(pool, root.nowMs) : null
                    readonly property color cdColor: root.stale ? root.dimTextColor
                        : (cd ? root.verdictColor(cd.verdict) : Kirigami.Theme.textColor)
                    Layout.fillWidth: true
                    // Every column gets the same slice of the panel; the name elides instead.
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    spacing: Kirigami.Units.smallSpacing * 2

                    // Name, with the countdown under it only when there is something to
                    // count down to; a quiet pool keeps just its name, centred.
                    ColumnLayout {
                        Layout.fillHeight: true
                        Layout.maximumWidth: poolColumn.width * 0.5
                        // The countdown row cannot elide; cut it off rather than paint over
                        // the bars when the panel slot is narrow.
                        clip: true
                        spacing: 0
                        visible: poolColumn.pool !== null
                        // Layouts fill by default; the bars take the slack instead.
                        Layout.fillWidth: false

                        Item { Layout.fillHeight: true }
                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: poolColumn.pool ? poolColumn.pool.label : ""
                            font: Kirigami.Theme.smallFont
                            opacity: 0.8
                        }
                        Row {
                            visible: poolColumn.cd !== null
                            spacing: Kirigami.Units.smallSpacing
                            PlasmaComponents3.Label {
                                visible: poolColumn.cd !== null && poolColumn.cd.back
                                anchors.baseline: countdownValue.baseline
                                text: "back"
                                font: Kirigami.Theme.smallFont
                                color: root.dimTextColor
                            }
                            PlasmaComponents3.Label {
                                id: countdownValue
                                text: poolColumn.cd ? poolColumn.cd.value : ""
                                font.bold: true
                                color: poolColumn.cdColor
                            }
                            PlasmaComponents3.Label {
                                anchors.baseline: countdownValue.baseline
                                text: poolColumn.cd ? poolColumn.cd.window : ""
                                font: Kirigami.Theme.smallFont
                                color: root.dimTextColor
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumWidth: Kirigami.Units.gridUnit
                        spacing: Kirigami.Units.mediumSpacing

                        Item { Layout.fillHeight: true }
                        ProjectionBar {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 5
                            win: poolColumn.pool ? poolColumn.pool.windows["5h"] : null
                            dimmed: root.stale
                        }
                        ProjectionBar {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 5
                            win: poolColumn.pool ? poolColumn.pool.windows["7d"] : null
                            dimmed: root.stale
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }

        Kirigami.Icon {
            anchors.top: parent.top
            anchors.right: parent.right
            width: Kirigami.Units.iconSizes.small
            height: width
            visible: root.unhealthy || root.lastError !== ""
            source: "data-warning"
        }

        // Plasma gives panel applets no resize handles of their own (the stock Panel Spacer
        // only exposes a width in its config dialog), so provide one grip per edge. Dragging
        // away from the centre grows the widget, toward it shrinks — correct on either side no
        // matter which edge the panel layout happens to pin.
        Repeater {
            model: [-1, 1] // -1 = leading edge, 1 = trailing edge
            delegate: MouseArea {
                id: grip
                required property var modelData
                readonly property int sign: modelData

                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: sign < 0 ? parent.left : undefined
                anchors.right: sign > 0 ? parent.right : undefined
                width: 6
                hoverEnabled: true
                cursorShape: Qt.SizeHorCursor
                // Keep the press away from compactRoot so a drag never toggles the popup.
                preventStealing: true

                property real pressSceneX: 0
                property int pressWidth: 0
                property bool moved: false

                onPressed: mouse => {
                    grip.pressSceneX = grip.mapToItem(null, mouse.x, 0).x;
                    grip.pressWidth = root.effectiveWidth;
                    grip.moved = false;
                }
                onPositionChanged: mouse => {
                    if (!grip.pressed)
                        return;
                    // Scene coordinates: the widget's own edges shift as it grows, local ones
                    // would feed back into the delta.
                    const delta = grip.mapToItem(null, mouse.x, 0).x - grip.pressSceneX;
                    if (!grip.moved && Math.abs(delta) < 2)
                        return;
                    grip.moved = true;
                    root.dragWidth = Math.round(grip.pressWidth + grip.sign * delta);
                }
                onReleased: {
                    if (grip.moved)
                        Plasmoid.configuration.panelWidth = root.effectiveWidth;
                    else
                        root.expanded = !root.expanded; // a plain click on the grip still toggles
                    root.dragWidth = -1;
                }
                onCanceled: root.dragWidth = -1

                // Discoverability: a hairline that fades in under the cursor.
                Rectangle {
                    anchors.centerIn: parent
                    width: 2
                    height: parent.height * 0.6
                    radius: 1
                    color: Kirigami.Theme.highlightColor
                    opacity: grip.containsMouse || grip.pressed ? 0.8 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: Kirigami.Units.shortDuration }
                    }
                }
            }
        }
    }

    fullRepresentation: ColumnLayout {
        id: popup
        Layout.preferredWidth: Kirigami.Units.gridUnit * 31
        Layout.preferredHeight: Kirigami.Units.gridUnit * 24
        spacing: Kirigami.Units.smallSpacing

        readonly property real laneHeight: Math.round(Kirigami.Theme.smallFont.pointSize * 1.6)
        readonly property real rowHeight: laneHeight + Kirigami.Units.smallSpacing * 2
        readonly property real gutter: Kirigami.Units.gridUnit * 4.5
        readonly property var headline: root.availabilityHeadline(root.pools, root.nowMs)

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Error
            visible: root.lastError !== ""
            text: root.lastError
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Warning
            visible: root.unhealthy
            text: {
                const msgs = [];
                if (root.stale)
                    msgs.push("Estimates are " + root.duration(root.nowMs - root.generatedAt) + " old: the daemon isn't updating.");
                if (root.pollError !== "")
                    msgs.push("omp: " + root.pollError);
                if (root.historyError !== "")
                    msgs.push("omp history: " + root.historyError);
                return msgs.join("\n");
            }
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: root.pools.length === 0 && root.lastError === ""
            text: (root.loading && !root.everLoaded)
                ? "Loading…"
                : "No estimates yet. Check that the claude-usage-estimator daemon is running."
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: root.pools.length > 0
            elide: Text.ElideRight
            text: popup.headline[0]
            font.weight: Font.DemiBold
            color: root.verdictColor(popup.headline[1])
        }

        // Lockout timeline, one lane per pool.
        Item {
            id: timeline
            Layout.fillWidth: true
            visible: root.pools.length > 0
            readonly property real laneX: popup.gutter
            readonly property real laneW: Math.max(0, width - laneX)
            readonly property real tickRow: Kirigami.Theme.smallFont.pointSize * 1.9
            readonly property int rows: root.pools.length
            implicitHeight: tickRow + rows * popup.rowHeight

            Repeater {
                model: root.timelineTicks(root.nowMs, timeline.laneW, Kirigami.Units.gridUnit * 2.5)
                delegate: Item {
                    required property var modelData
                    required property int index
                    readonly property real px: timeline.laneX + timeline.laneW * root.axisFraction(modelData.t, root.nowMs)

                    Rectangle {
                        x: parent.px - 0.5
                        y: timeline.tickRow
                        width: 1
                        height: timeline.height - timeline.tickRow
                        color: root.ruleColor
                    }
                    PlasmaComponents3.Label {
                        x: parent.index === 0 ? parent.px : parent.px - width / 2
                        text: parent.modelData.label
                        font: Kirigami.Theme.smallFont
                        color: root.dimTextColor
                    }
                }
            }
            // The axis changes scale after the first day.
            Rectangle {
                x: timeline.laneX + timeline.laneW * 0.5 - 0.5
                y: timeline.tickRow * 0.4
                width: 1
                height: timeline.height - y
                color: root.dimTextColor
                opacity: 0.6
            }

            Repeater {
                model: root.pools
                delegate: Item {
                    required property var modelData
                    required property int index
                    readonly property var blocks: root.poolBlocks(modelData, root.nowMs)
                    readonly property var main: blocks.filter(b => b.kind === "bad").sort((p, q) => p.from - q.from)[0]
                    y: timeline.tickRow + index * popup.rowHeight
                    width: timeline.width
                    height: popup.rowHeight

                    PlasmaComponents3.Label {
                        width: popup.gutter - Kirigami.Units.smallSpacing
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: parent.modelData.label
                        font.weight: Font.DemiBold
                    }
                    Lane {
                        id: lane
                        x: timeline.laneX
                        width: timeline.laneW
                        height: popup.laneHeight
                        anchors.verticalCenter: parent.verticalCenter
                        blocks: parent.blocks
                        readonly property var span: parent.main
                        readonly property real x1: span ? width * root.axisFraction(Math.max(root.nowMs, span.from), root.nowMs) : 0
                        readonly property real x2: span ? width * root.axisFraction(span.until, root.nowMs) : 0
                        annotation: span && x2 - x1 > Kirigami.Units.gridUnit * 7
                            ? root.shortTime(span.from, root.nowMs) + " → " + root.shortTime(span.until, root.nowMs)
                            : ""
                        annotationX: x1
                    }
                }
            }
        }

        PlasmaComponents3.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.pools.length > 0

            ListView {
                model: root.pools
                spacing: Kirigami.Units.smallSpacing
                clip: true

                delegate: ColumnLayout {
                    id: poolSection
                    required property var modelData
                    readonly property var status: root.poolStatus(modelData, root.nowMs)
                    width: ListView.view ? ListView.view.width : 0
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Separator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: poolSection.modelData.label
                            font.bold: true
                        }
                        PlasmaComponents3.Label {
                            text: poolSection.status[0]
                            font.weight: Font.DemiBold
                            color: root.verdictColor(poolSection.status[1])
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.largeSpacing * 2
                        Repeater {
                            model: ["5h", "7d"]
                            delegate: ChartCell {
                                required property string modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.minimumWidth: 0
                                win: poolSection.modelData.windows[modelData]
                                points: root.poolPoints(poolSection.modelData, "anthropic:" + modelData)
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents3.Label {
                visible: root.generatedAt > 0
                text: "Updated " + new Date(root.generatedAt).toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
                font: Kirigami.Theme.smallFont
                color: root.dimTextColor
            }
            Item { Layout.fillWidth: true }
            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh"
                onClicked: {
                    root.refresh();
                    root.refreshSamples();
                }
            }
        }
    }
}
