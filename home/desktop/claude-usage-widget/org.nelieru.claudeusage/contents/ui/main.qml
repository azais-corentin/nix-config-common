import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Last good snapshot from `claude-usage-estimator get --json`, one pool per provider:
    //   [{ provider, label, members: [account], windows: [win], block, verdict }]
    // windows are sorted shortest first.
    // win: { key, limit, windowMs, state, used, start, resetsAt, forecast, verdict, runsOut,
    //        outAt, outEarly, out, of }, times in unix ms, fractions in 0..1; `used` is the
    //        mean over the pool, `out` of the `of` accounts are out of this window now.
    //        key: "5h", "7d" or "30d".
    // block: the window that makes the pool unusable soonest (exhausted now, else the
    //        earliest median run-out): { from, until, key, exhausted } or null.
    property var pools: []
    // Daemon health carried by the snapshot.
    property double generatedAt: 0
    property string pollError: ""
    property string historyError: ""
    // Stored samples of the last month, keyed "account|limit" -> [[t, used], …] sorted by t.
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

    /** Display names of the providers the daemon reports, in display order. */
    readonly property var providerLabels: ({ "anthropic": "Claude", "opencode-go": "OpenCode Go" })
    readonly property var providerOrder: ["anthropic", "opencode-go"]

    // Verdict colours from the desktop's Monokai Pro Spectrum palette. Fixed rather than
    // theme roles: the stylix scheme maps neutralTextColor to cyan.
    readonly property var verdictColors: ({ "ok": "#7bd88f", "warn": "#fce566", "bad": "#fc618d" })
    // Time still usable on the popup timeline: neutral, so pink alone means "out".
    readonly property color availableColor: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                                    Kirigami.Theme.textColor.b, 0.12)
    readonly property color ruleColor: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                               Kirigami.Theme.textColor.b, 0.1)
    // Secondary text. Opaque so it also works in Canvas and StyledText, and derived from the
    // text colour because the stylix scheme sets inactive/disabled text equal to normal text.
    readonly property color dimTextColor: Qt.tint(Kirigami.Theme.backgroundColor,
                                                  Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                                          Kirigami.Theme.textColor.b, 0.75))
    readonly property var weekdays: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    function verdictColor(v) {
        return verdictColors[v] || verdictColors.ok;
    }

    /** How full a window is, independent of the forecast: pink once exhausted, else text. */
    function usageColor(win) {
        return win.state === "exhausted" ? verdictColors.bad : Kirigami.Theme.textColor;
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

    /** "17:15" today, "Wed 16:00" within the week, else "12 Nov". */
    function shortTime(t, now) {
        const dd = dayDelta(t, now);
        if (dd === 0)
            return hm(t);
        if (dd > -7 && dd < 7)
            return weekdays[new Date(t).getDay()] + " " + hm(t);
        return Qt.formatDate(new Date(t), "d MMM");
    }

    /** "17:15", "tomorrow 16:00", "Wed 16:00" or "12 Nov". */
    function longTime(t, now) {
        return dayDelta(t, now) === 1 ? "tomorrow " + hm(t) : shortTime(t, now);
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

    /** "5h", "7d" or "30d" from a window length. */
    function windowKey(windowMs) {
        if (windowMs <= 6 * hourMs)
            return "5h";
        return windowMs <= 8 * dayMs ? "7d" : "30d";
    }

    /** Rounds a run-out time to what the forecast resolves: 5 min (5h) or 1 h (longer). */
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
            "key": windowKey(e.windowMs),
            "limit": e.limit,
            "windowMs": e.windowMs,
            "state": e.state,
            "used": e.used,
            "start": start,
            "resetsAt": resetsAt,
            "forecast": f,
            "verdict": verdict,
            "runsOut": runsOut,
            "outAt": runsOut ? r(f.emptyAt.p50) : null,
            "outEarly": f ? r(f.emptyAt.p10) : null,
            "out": e.exhausted || 0,
            "of": e.accounts || 1
        };
    }

    function normalizePool(p, now) {
        const ws = (p.windows || []).map(normalizeWindow).sort((x, y) => x.windowMs - y.windowMs);
        const ex = ws.filter(w => w.state === "exhausted" && w.resetsAt !== null)
            .sort((x, y) => y.resetsAt - x.resetsAt)[0];
        const outs = ws.filter(w => w.runsOut).sort((x, y) => x.outAt - y.outAt);
        let block = null;
        if (ex)
            block = { "from": now, "until": ex.resetsAt, "key": ex.key, "exhausted": true };
        else if (outs.length > 0)
            block = { "from": outs[0].outAt, "until": outs[0].resetsAt, "key": outs[0].key, "exhausted": false };
        return {
            "provider": p.provider,
            "label": providerLabels[p.provider] || p.provider,
            "members": (p.accounts || []).map(a => a.account),
            "windows": ws,
            "block": block,
            "verdict": ws.some(w => w.verdict === "bad") ? "bad" : (ws.some(w => w.verdict === "warn") ? "warn" : "ok")
        };
    }

    /** Predicted unavailability of one window: [{ from, until, kind }]: "bad" from the
     *  median run-out, "warn" (half strength) from the earliest plausible one when a run-out
     *  is likely (>= 25 %). */
    function windowBlocks(win, now) {
        if (!win || win.resetsAt === null)
            return [];
        if (win.state === "exhausted")
            return [{ "from": now, "until": win.resetsAt, "kind": "bad" }];
        if (win.runsOut)
            return [{ "from": win.outAt, "until": win.resetsAt, "kind": "bad" }];
        if (win.verdict === "warn" && win.outEarly !== null)
            return [{ "from": win.outEarly, "until": win.resetsAt, "kind": "warn" }];
        return [];
    }

    function poolBlocks(pool, now) {
        return pool.windows.reduce((acc, w) => acc.concat(windowBlocks(w, now)), []);
    }

    /** The panel's countdown slot: null while the pool is on track. */
    function countdown(pool, now) {
        const b = pool.block;
        if (b !== null && b.exhausted)
            return { "back": true, "value": duration(b.until - now), "verdict": "bad" };
        if (b !== null)
            return { "back": false, "value": duration(b.from - now), "verdict": "bad" };
        if (pool.verdict === "warn") {
            const ws = pool.windows.filter(w => w.verdict === "warn")
                .sort((x, y) => y.forecast.pEmpty - x.forecast.pEmpty);
            return { "back": false, "value": pct(ws[0].forecast.pEmpty) + " risk", "verdict": "warn" };
        }
        return null;
    }

    /** The popup's per-pool headline: [text, verdict]. */
    function poolStatus(pool, now) {
        const b = pool.block;
        if (b !== null && b.exhausted)
            return ["Out until " + longTime(b.until, now), "bad"];
        if (b !== null)
            return ["Out " + longTime(b.from, now) + " – back " + longTime(b.until, now), "bad"];
        if (pool.verdict === "warn")
            return ["Might run out", "warn"];
        return ["Available", "ok"];
    }

    /** Pooled usage history of one window, [[t, used], …]: the members' sample series merged
     *  by time, each member holding its latest `used` (0 before its first sample), averaged
     *  over the window's `of` accounts. */
    function poolPoints(pool, win) {
        const events = [];
        pool.members.forEach((m, i) => {
            for (const s of samples[m + "|" + win.limit] || [])
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

    /** Where the popup timeline's log axis starts: anything sooner sits on its left edge. */
    readonly property double axisStartMs: 5 * minuteMs
    /** How far the popup timeline looks ahead: the farthest reset of any window (at least a
     *  week, at most a month), so every predicted outage fits. */
    readonly property double axisHorizonMs: {
        let h = 7 * dayMs;
        for (const p of pools)
            for (const w of p.windows)
                if (w.resetsAt !== null)
                    h = Math.max(h, w.resetsAt - nowMs);
        return Math.min(h, 31 * dayMs);
    }

    /** Position on the popup timeline, 0..1, logarithmic in the time from now. */
    function axisFraction(t, now) {
        const dt = Math.max(axisStartMs, t - now);
        return Math.min(1, Math.log(dt / axisStartMs) / Math.log(axisHorizonMs / axisStartMs));
    }

    /** Timeline ticks: [{ t, label, span }] at round spans from now within the horizon; a
     *  label that would overlap one already placed is dropped, `labelWidth(text)` measuring
     *  it in px. */
    function timelineTicks(now, laneWidth, labelWidth, gap) {
        const marks = [[5 * minuteMs, "5m"], [hourMs, "1h"], [dayMs, "1d"], [7 * dayMs, "1w"]];
        const placed = [];
        for (const m of marks) {
            if (m[0] > axisHorizonMs)
                break;
            // Centred on its tick, but kept inside the lane at either end.
            const x = laneWidth * axisFraction(now + m[0], now), w = labelWidth(m[1]);
            const left = Math.max(0, Math.min(x - w / 2, laneWidth - w));
            const s = [left, left + w];
            if (placed.every(p => s[1] + gap <= p.span[0] || s[0] >= p.span[1] + gap))
                placed.push({ "t": now + m[0], "label": m[1], "span": s });
        }
        return placed;
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
        const now = snap.generatedAt || Date.now();
        const rank = p => {
            const i = providerOrder.indexOf(p.provider);
            return i < 0 ? providerOrder.length : i;
        };
        pools = (snap.providers || []).filter(p => (p.windows || []).length > 0)
            .sort((p, q) => rank(p) - rank(q))
            .map(p => normalizePool(p, now));
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
        // Current windows start at most 30 d ago; keep a little slack for the window start.
        const since = Date.now() - 30 * dayMs - hourMs;
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

    toolTipMainText: "AI usage"
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
            lines.push("<b>" + p.label + "</b>");
            for (const w of p.windows) {
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
                lines.push(w.key + " " + pct(w.used) + ", " + tail + outs);
            }
        }
        return lines.join("<br>");
    }

    // Availability lane on the popup timeline: neutral while usable, pink and striped from
    // the median run-out to the reset.
    component Lane: Item {
        id: lane
        property var blocks: []

        /** The outages: overlapping "bad" blocks merged, clipped to now. */
        readonly property var spans: {
            const bad = blocks.filter(b => b.kind === "bad" && b.until > root.nowMs)
                .map(b => ({ "from": Math.max(root.nowMs, b.from), "until": b.until }))
                .sort((p, q) => p.from - q.from);
            const out = [];
            for (const b of bad) {
                if (out.length > 0 && b.from <= out[out.length - 1].until)
                    out[out.length - 1].until = Math.max(out[out.length - 1].until, b.until);
                else
                    out.push(b);
            }
            return out;
        }

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
                readonly property real x1: lane.width * root.axisFraction(Math.max(root.nowMs, modelData.from), root.nowMs)
                readonly property real x2: lane.width * root.axisFraction(modelData.until, root.nowMs)
                readonly property color tone: root.verdictColor(modelData.kind)
                anchors.fill: parent
                visible: x2 > 0 && x1 < lane.width

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
        // Stripes over each outage, so "out" does not rest on colour alone.
        Canvas {
            id: stripes
            anchors.fill: parent
            readonly property var spans: lane.spans
            onSpansChanged: requestPaint()
            onWidthChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.strokeStyle = Kirigami.Theme.backgroundColor.toString();
                ctx.globalAlpha = 0.18;
                ctx.lineWidth = 2;
                for (const s of spans) {
                    const x1 = width * root.axisFraction(s.from, root.nowMs);
                    const x2 = width * root.axisFraction(s.until, root.nowMs);
                    ctx.save();
                    ctx.beginPath();
                    ctx.rect(x1, 0, x2 - x1, height);
                    ctx.clip();
                    ctx.beginPath();
                    for (let x = x1 - height; x < x2; x += 6) {
                        ctx.moveTo(x, height);
                        ctx.lineTo(x + height, 0);
                    }
                    ctx.stroke();
                    ctx.restore();
                }
            }
        }
    }

    // Burn-up chart of one window: x = window start → reset, y = 0 → 100 %. Usage so far as
    // a neutral step curve (straight line until samples load), the neutral forecast band
    // (10th–90th percentile) and dashed median, and in pink only the predicted outage.
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
            // A pooled window can report a start after now; the axis then begins at now.
            const start = Math.min(win.start, now);
            const tx = t => w * (t - start) / (win.resetsAt - start);
            const uy = u => h - (h - 1.5) * Math.min(1, u);

            ctx.save();
            ctx.beginPath();
            ctx.rect(0, 0, w, h);
            ctx.clip();

            // Time grid by the axis span: full hours (up to 8 h), midnights (up to 8 d), else
            // Monday midnights.
            ctx.fillStyle = fg;
            ctx.globalAlpha = 0.09;
            const span = win.resetsAt - start;
            const hourly = span <= 8 * root.hourMs, weekly = span > 8 * root.dayMs;
            const s0 = new Date(start);
            let g = hourly
                ? new Date(s0.getFullYear(), s0.getMonth(), s0.getDate(), s0.getHours() + 1)
                : new Date(s0.getFullYear(), s0.getMonth(), s0.getDate() + 1);
            if (weekly)
                g = new Date(g.getFullYear(), g.getMonth(), g.getDate() + (8 - g.getDay()) % 7);
            for (; g.getTime() < win.resetsAt; ) {
                ctx.fillRect(Math.round(tx(g.getTime())) - 0.5, 0, 1, h);
                g = hourly ? new Date(g.getFullYear(), g.getMonth(), g.getDate(), g.getHours() + 1)
                           : new Date(g.getFullYear(), g.getMonth(), g.getDate() + (weekly ? 7 : 1));
            }
            ctx.globalAlpha = 1;

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
            if (now > start) {
                const pts = chart.points.filter(p => p[0] >= start && p[0] <= now);
                // History that begins well into the window, already above zero, was not
                // recorded rather than unused: start the curve at the first sample.
                const gap = pts.length > 0 && pts[0][1] > 0 && pts[0][0] - start > 0.02 * (win.resetsAt - start);
                const t0 = gap ? pts[0][0] : start;
                const path = () => {
                    let prev = gap ? pts[0][1] : 0;
                    ctx.moveTo(tx(t0), uy(prev));
                    if (pts.length === 0) {
                        ctx.lineTo(tx(now), uy(win.used));
                        return;
                    }
                    for (const p of gap ? pts.slice(1) : pts) {
                        ctx.lineTo(tx(p[0]), uy(prev));
                        ctx.lineTo(tx(p[0]), uy(p[1]));
                        prev = p[1];
                    }
                    ctx.lineTo(tx(now), uy(prev));
                    ctx.lineTo(tx(now), uy(win.used));
                };
                // What happened is neutral, pink only once exhausted.
                const hc = chart.dimmed ? root.dimTextColor.toString()
                    : (win.state === "exhausted" ? root.verdictColors.bad : fg);
                ctx.fillStyle = hc;
                ctx.globalAlpha = 0.16;
                ctx.beginPath();
                path();
                ctx.lineTo(tx(now), uy(0));
                ctx.lineTo(tx(t0), uy(0));
                ctx.closePath();
                ctx.fill();
                ctx.strokeStyle = hc;
                ctx.globalAlpha = 0.8;
                ctx.lineWidth = 1.4;
                ctx.beginPath();
                path();
                ctx.stroke();
            }

            // Forecast, neutral: the 10th–90th percentile band and the dashed median.
            ctx.fillStyle = fg;
            ctx.strokeStyle = fg;
            const f = win.state === "active" ? win.forecast : null;
            if (f) {
                const edge = (outT, atReset) => root.present(outT)
                    ? [[tx(outT), uy(1)], [tx(win.resetsAt), uy(1)]]
                    : [[tx(win.resetsAt), uy(atReset)]];
                const upper = edge(f.emptyAt.p10, f.atReset.p90);
                const lower = edge(f.emptyAt.p90, f.atReset.p10).reverse();
                ctx.globalAlpha = 0.1;
                ctx.beginPath();
                ctx.moveTo(tx(now), uy(win.used));
                for (const p of upper.concat(lower))
                    ctx.lineTo(p[0], p[1]);
                ctx.closePath();
                ctx.fill();
                ctx.globalAlpha = 0.6;
                ctx.lineWidth = 1.3;
                ctx.setLineDash([3, 2]);
                ctx.beginPath();
                ctx.moveTo(tx(now), uy(win.used));
                const mid = edge(f.emptyAt.p50, f.atReset.p50);
                ctx.lineTo(mid[0][0], mid[0][1]);
                ctx.stroke();
                ctx.setLineDash([]);
                ctx.globalAlpha = 1;
            }
            ctx.restore();

            // Now marker.
            ctx.globalAlpha = 0.55;
            ctx.fillStyle = fg;
            ctx.fillRect(tx(now) - 0.5, 0, 1, h);
            ctx.globalAlpha = 1;

            // The predicted outage, the only colour on the chart: from the median run-out
            // along the ceiling to the reset.
            if (win.runsOut && !chart.dimmed) {
                const dx = tx(win.forecast.emptyAt.p50);
                ctx.strokeStyle = root.verdictColors.bad;
                ctx.lineWidth = 3;
                ctx.beginPath();
                ctx.moveTo(dx, uy(1) + 1.5);
                ctx.lineTo(w, uy(1) + 1.5);
                ctx.stroke();
                ctx.fillStyle = root.verdictColors.bad;
                ctx.beginPath();
                ctx.arc(dx, uy(1) + 1.5, 3.5, 0, 2 * Math.PI);
                ctx.fill();
            }
        }
    }

    // One window of a pool in the popup: share used and the burn chart over the window, with
    // the reset time in its corner. While a window locks the pool (its `block`), that
    // window's name turns pink and the others step back.
    component WindowRow: ColumnLayout {
        id: row
        property var win: null
        property var points: []
        property var block: null
        readonly property bool binding: win !== null && block !== null && block.key === win.key
        opacity: block !== null && !binding ? 0.5 : 1
        spacing: 1

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing
            ColumnLayout {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                Layout.fillWidth: false
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                PlasmaComponents3.Label {
                    text: row.win ? root.pct(row.win.used) : "–"
                    font.bold: true
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
                    color: row.win ? root.usageColor(row.win) : root.dimTextColor
                }
                PlasmaComponents3.Label {
                    text: row.win ? row.win.key : ""
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    font.weight: row.binding ? Font.DemiBold : Font.Normal
                    color: row.binding ? root.verdictColors.bad : root.dimTextColor
                }
            }
            BurnChart {
                id: chart
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 2.4
                win: row.win
                points: row.points
                dimmed: root.stale

                // When the window resets, in the chart's bottom-right corner.
                PlasmaComponents3.Label {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: Kirigami.Units.smallSpacing
                    text: row.win && row.win.resetsAt !== null ? root.shortTime(row.win.resetsAt, root.nowMs) : ""
                    font: Kirigami.Theme.smallFont
                    color: root.dimTextColor
                }
            }
        }
    }

    compactRepresentation: MouseArea {
        id: compactRoot
        // One entry per pool; a single null column keeps the slot laid out before the first
        // successful poll.
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
            spacing: Kirigami.Units.largeSpacing

            Repeater {
                model: compactRoot.columns
                delegate: RowLayout {
                    id: poolColumn
                    required property var modelData
                    required property int index
                    readonly property var pool: modelData
                    readonly property var cd: pool ? root.countdown(pool, root.nowMs) : null
                    readonly property color cdColor: root.stale ? root.dimTextColor
                        : (cd ? root.verdictColor(cd.verdict) : Kirigami.Theme.textColor)
                    Layout.fillWidth: true
                    // Every column gets the same slice of the panel; the name elides instead.
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    spacing: Kirigami.Units.smallSpacing * 2

                    // Hairline between providers.
                    Rectangle {
                        visible: poolColumn.index > 0
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        Layout.topMargin: Kirigami.Units.mediumSpacing
                        Layout.bottomMargin: Kirigami.Units.mediumSpacing
                        color: root.ruleColor
                    }
                    // Name, with the countdown under it only when there is something to
                    // count down to; a quiet pool keeps just its name, centred.
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        // The countdown row cannot elide; cut it off when the slot is narrow.
                        clip: true
                        spacing: 0
                        visible: poolColumn.pool !== null

                        Item { Layout.fillHeight: true }
                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: poolColumn.pool ? poolColumn.pool.label : ""
                            font: Kirigami.Theme.smallFont
                            opacity: 0.8
                            // Fractional text widths otherwise elide a label that fits.
                            Layout.preferredWidth: Math.ceil(implicitWidth) + 1
                        }
                        Row {
                            visible: poolColumn.cd !== null
                            spacing: Kirigami.Units.smallSpacing
                            PlasmaComponents3.Label {
                                visible: poolColumn.cd !== null && poolColumn.cd.verdict === "bad"
                                anchors.baseline: countdownValue.baseline
                                text: poolColumn.cd && poolColumn.cd.back ? "back in" : "out in"
                                font: Kirigami.Theme.smallFont
                                color: root.dimTextColor
                            }
                            PlasmaComponents3.Label {
                                id: countdownValue
                                text: poolColumn.cd ? poolColumn.cd.value : ""
                                font.bold: true
                                color: poolColumn.cdColor
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
            }

            // Daemon trouble: takes its own slot rather than covering the text.
            Kirigami.Icon {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                visible: root.unhealthy || root.lastError !== ""
                source: "data-warning"
            }
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

    fullRepresentation: Item {
        // Sized to the content: nothing scrolls and nothing stretches.
        implicitWidth: Kirigami.Units.gridUnit * 31
        implicitHeight: content.implicitHeight + Kirigami.Units.smallSpacing
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: implicitWidth
        Layout.maximumWidth: implicitWidth
        Layout.minimumHeight: implicitHeight
        Layout.preferredHeight: implicitHeight
        Layout.maximumHeight: implicitHeight

        PopupContent {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
        }
    }

    // The popup, top to bottom: daemon trouble, the availability timeline with one lane per
    // pool, then one section per pool with a burn chart per window.
    component PopupContent: ColumnLayout {
        id: popup
        spacing: Kirigami.Units.smallSpacing

        readonly property real laneHeight: Math.round(Kirigami.Theme.smallFont.pointSize * 1.6)
        readonly property real rowHeight: laneHeight + Kirigami.Units.smallSpacing * 2
        readonly property real gutter: Kirigami.Units.gridUnit * 6

        FontMetrics {
            id: tickMetrics
            font: Kirigami.Theme.smallFont
        }

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
                model: root.timelineTicks(root.nowMs, timeline.laneW, s => tickMetrics.advanceWidth(s),
                                          Kirigami.Units.largeSpacing * 1.5)
                delegate: Item {
                    required property var modelData
                    readonly property real px: timeline.laneX + timeline.laneW * root.axisFraction(modelData.t, root.nowMs)

                    Rectangle {
                        x: parent.px - 0.5
                        y: timeline.tickRow
                        width: 1
                        height: timeline.height - timeline.tickRow
                        color: root.ruleColor
                    }
                    PlasmaComponents3.Label {
                        x: timeline.laneX + parent.modelData.span[0]
                        text: parent.modelData.label
                        font: Kirigami.Theme.smallFont
                        color: root.dimTextColor
                    }
                }
            }

            Repeater {
                model: root.pools
                delegate: Item {
                    required property var modelData
                    required property int index
                    readonly property var blocks: root.poolBlocks(modelData, root.nowMs)
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
                        x: timeline.laneX
                        width: timeline.laneW
                        height: popup.laneHeight
                        anchors.verticalCenter: parent.verticalCenter
                        blocks: parent.blocks
                    }
                }
            }
        }

        Repeater {
            model: root.pools
            delegate: ColumnLayout {
                id: poolSection
                required property var modelData
                readonly property var status: root.poolStatus(modelData, root.nowMs)
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Separator {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing * 2
                    PlasmaComponents3.Label {
                        text: poolSection.modelData.label
                        font.bold: true
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignBaseline
                        elide: Text.ElideRight
                        // Only when it explains an outage: some accounts are already out.
                        text: {
                            const p = poolSection.modelData;
                            const out = Math.max(0, ...p.windows.map(w => w.out));
                            return out > 0 ? out + " of " + p.members.length + " accounts out" : "";
                        }
                        font: Kirigami.Theme.smallFont
                        color: root.dimTextColor
                    }
                    PlasmaComponents3.Label {
                        text: poolSection.status[0]
                        font.weight: Font.DemiBold
                        color: poolSection.status[1] === "ok" ? root.dimTextColor : root.verdictColor(poolSection.status[1])
                    }
                }

                Repeater {
                    model: poolSection.modelData.windows
                    delegate: WindowRow {
                        required property var modelData
                        Layout.fillWidth: true
                        win: modelData
                        points: root.poolPoints(poolSection.modelData, modelData)
                        block: poolSection.modelData.block
                    }
                }
            }
        }
    }
}
