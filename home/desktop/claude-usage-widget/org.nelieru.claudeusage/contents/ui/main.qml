import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Last good snapshot from `claude-usage-estimator get --json`, one pool per provider:
    //   [{ provider, label, short, members: [account], accounts: [acct], windows: [win],
    //      block, verdict }]
    // windows are sorted shortest first.
    // win: { key, limit, windowMs, state, used, start, resetsAt, forecast, verdict, runsOut,
    //        outAt, outEarly, outLate, out, of }, times in unix ms, fractions in 0..1; `used`
    //        is the mean over the pool, `out` of the `of` accounts are out of this window now.
    //        key: "5h", "7d" or "30d".
    // acct: { name, share, windows }: `share` of the provider's capacity (null unless the
    //        estimator weighs the pool), `windows` the account's own, raw from the daemon.
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

    /** Bounds for the panel's text line, in px; the rings add 36 px per provider. Mirrored by
     *  the config spin box. */
    readonly property int minTextWidth: 0
    readonly property int maxTextWidth: 400
    /** >= 0 only while a resize grip is being dragged; overrides the stored width live so the
     *  drag stays smooth without writing config on every mouse move. */
    property int dragTextWidth: -1
    readonly property int textWidth: Math.max(minTextWidth, Math.min(maxTextWidth,
        dragTextWidth >= 0 ? dragTextWidth : Plasmoid.configuration.textWidth))
    /** Rings shown in the panel: one per pool, or one per known provider before the first poll. */
    readonly property int ringCount: pools.length > 0 ? pools.length : providerOrder.length
    readonly property int panelWidth: 4 + ringCount * 32 + (ringCount - 1) * 4 + 8 + textWidth + 4

    /** Display names of the providers the daemon reports, in display order. */
    readonly property var providerLabels: ({ "anthropic": "Claude", "opencode-go": "OpenCode Go" })
    /** The names under the panel rings. */
    readonly property var providerShortLabels: ({ "anthropic": "Claude", "opencode-go": "Go" })
    readonly property var providerOrder: ["anthropic", "opencode-go"]

    // Verdict colours from the desktop's Monokai Pro Spectrum palette. Fixed rather than
    // theme roles: the stylix scheme maps neutralTextColor to cyan.
    readonly property var verdictColors: ({ "ok": "#7bd88f", "warn": "#fce566", "bad": "#fc618d" })
    readonly property color textColor: Kirigami.Theme.textColor
    // Secondary text. Opaque so it also works in Canvas and StyledText, and derived from the
    // text colour because the stylix scheme sets inactive/disabled text equal to normal text.
    readonly property color dimTextColor: Qt.tint(Kirigami.Theme.backgroundColor, textAlpha(0.75))
    readonly property var weekdays: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    readonly property var months: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    function textAlpha(a) {
        return Qt.rgba(textColor.r, textColor.g, textColor.b, a);
    }

    function verdictColor(v) {
        return verdictColors[v] || verdictColors.ok;
    }

    /** Point size of a font sized `px` logical pixels. */
    function pt(px) {
        return px * 0.75;
    }

    function clamp01(x) {
        return Math.max(0, Math.min(1, x));
    }

    function pct(f) {
        return Math.round(f * 100) + "%";
    }

    function pace(f) {
        return f.pace.toFixed(1) + "×";
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
        return dayMonth(t);
    }

    /** "12 Nov". */
    function dayMonth(t) {
        const d = new Date(t);
        return d.getDate() + " " + months[d.getMonth()];
    }

    /** "17:15", "tomorrow 16:00", "Wed 16:00" or "12 Nov". */
    function longTime(t, now) {
        return dayDelta(t, now) === 1 ? "tomorrow " + hm(t) : shortTime(t, now);
    }

    /** "2h 18m", "3d 2h", "45m", "now"; `compact` drops the spaces: "2h18", "3d2h". */
    function duration(ms, compact) {
        let m = Math.round(ms / minuteMs);
        if (m < 1)
            return "now";
        const d = Math.floor(m / 1440);
        m -= d * 1440;
        const h = Math.floor(m / 60);
        m -= h * 60;
        if (d > 0)
            return compact ? d + "d" + h + "h" : d + "d " + h + "h";
        if (h > 0)
            return compact ? h + "h" + pad2(m) : h + "h " + pad2(m) + "m";
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

    /** `s` safe inside StyledText. */
    function escaped(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    /** StyledText of [{ t, c }] segments. */
    function styled(segs) {
        return segs.map(s => "<font color=\"" + s.c + "\">" + escaped(s.t) + "</font>").join("");
    }

    /** styled(segs), wrapped at `width` like CSS `text-wrap: pretty`: when the last line
     *  would be shorter than a quarter of the width, the line above hands it its last word.
     *  `metrics` measures the text's font. */
    function prettyStyled(segs, metrics, width) {
        const words = segs.map(s => s.t).join("").split(" ");
        const lines = [[]];
        for (const w of words) {
            const line = lines[lines.length - 1];
            if (line.length > 0 && metrics.advanceWidth(line.concat(w).join(" ")) > width)
                lines.push([w]);
            else
                line.push(w);
        }
        const n = lines.length;
        if (n < 2 || lines[n - 2].length < 2 || metrics.advanceWidth(lines[n - 1].join(" ")) >= width / 4)
            return styled(segs);
        // The space before the last word of the line above the last.
        const k = lines.slice(0, n - 1).reduce((a, l) => a + l.length, 0) - 1;
        let cut = words.slice(0, k).reduce((a, w) => a + w.length + 1, 0) - 1;
        return segs.map(s => {
            const at = cut;
            cut -= s.t.length;
            const color = "<font color=\"" + s.c + "\">";
            if (at < 0 || at >= s.t.length)
                return color + escaped(s.t) + "</font>";
            return color + escaped(s.t.slice(0, at)) + "<br>" + escaped(s.t.slice(at + 1)) + "</font>";
        }).join("");
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
            "outLate": f ? r(f.emptyAt.p90) : null,
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
        // An account's share of the pool, from the longest window's capacity.
        const longest = ws.length > 0 ? ws[ws.length - 1].limit : null;
        const accounts = (p.accounts || []).map(a => {
            const cap = (a.capacity || []).find(c => c.limit === longest);
            return {
                "name": a.account,
                "share": cap && present(cap.share) ? cap.share : null,
                "windows": a.windows || []
            };
        });
        return {
            "provider": p.provider,
            "label": providerLabels[p.provider] || p.provider,
            "short": providerShortLabels[p.provider] || p.provider,
            "members": accounts.map(a => a.name),
            "accounts": accounts,
            "windows": ws,
            "block": block,
            "verdict": ws.some(w => w.verdict === "bad") ? "bad" : (ws.some(w => w.verdict === "warn") ? "warn" : "ok")
        };
    }

    /** Usage the median forecast lands on at reset, else usage now. */
    function projected(w) {
        return w.forecast ? w.forecast.atReset.p50 : w.used;
    }

    /** The window that speaks for a pool: the blocking one, else the riskiest, else the one
     *  projected fullest. */
    function bindingWindow(p) {
        if (p.block !== null)
            return p.windows.find(w => w.key === p.block.key);
        const risky = p.windows.filter(w => w.verdict === "warn")
            .sort((a, b) => b.forecast.pEmpty - a.forecast.pEmpty);
        if (risky.length > 0)
            return risky[0];
        return p.windows.slice().sort((a, b) => projected(b) - projected(a))[0];
    }

    /** A pool at a glance: kind "back" (out now), "out" (runs out), "warn" or "ok". */
    function glance(p, now) {
        const b = p.block, bw = bindingWindow(p);
        if (b !== null && b.exhausted)
            return { "kind": "back", "big": duration(b.until - now), "bw": bw };
        if (b !== null)
            return { "kind": "out", "big": duration(b.from - now), "bw": bw };
        return { "kind": p.verdict === "warn" ? "warn" : "ok", "big": "", "bw": bw };
    }

    function glanceColor(kind) {
        return kind === "ok" ? textColor : verdictColor(kind === "warn" ? "warn" : "bad");
    }

    /** The pool the panel and the popup headline speak about: the first to run out, else
     *  one at risk, else the one resetting soonest. */
    function urgentPool(ps) {
        const blocked = ps.filter(p => p.block !== null).sort((a, b) => a.block.from - b.block.from);
        if (blocked.length > 0)
            return blocked[0];
        const risky = ps.find(p => p.verdict === "warn");
        if (risky)
            return risky;
        const reset = p => {
            const t = bindingWindow(p).resetsAt;
            return t === null ? Infinity : t;
        };
        return ps.slice().sort((a, b) => reset(a) - reset(b))[0];
    }

    /** A pool's one-line status in its popup section: [text, colour]. */
    function poolStatus(p, now) {
        const b = p.block, bw = bindingWindow(p);
        if (b !== null && b.exhausted)
            return ["out · back " + longTime(b.until, now), verdictColors.bad];
        if (b !== null)
            return ["out " + longTime(b.from, now) + " · back " + longTime(b.until, now), verdictColors.bad];
        if (p.verdict === "warn")
            return [pct(bw.forecast.pEmpty) + " risk before " + shortTime(bw.resetsAt, now), verdictColors.warn];
        if (bw.resetsAt === null)
            return [bw.key + " " + pct(bw.used), dimTextColor];
        return [bw.key + " " + pct(bw.used) + " · resets in " + duration(bw.resetsAt - now), dimTextColor];
    }

    /** The panel: rings, two lines about the urgent pool, the trouble icon. */
    readonly property var panelView: {
        const now = nowMs;
        const warn = unhealthy || lastError !== "";
        if (pools.length === 0)
            return {
                "rings": providerOrder.map(p => ({ "label": providerShortLabels[p], "used": 0, "color": dimTextColor, "text": "" })),
                "line1": "Connecting…", "line2": "—", "color": dimTextColor, "warn": warn, "opacity": 1
            };
        const rings = pools.map(p => {
            const g = glance(p, now), u = clamp01(g.bw.used);
            return { "label": p.short, "used": u, "color": glanceColor(g.kind), "text": String(Math.round(u * 100)) };
        });
        // The short name, as under the rings: the line is narrow.
        const u = urgentPool(pools), g = glance(u, now), bw = g.bw;
        let line1, line2;
        if (g.kind === "back") {
            line1 = u.short + " back in";
            line2 = g.big;
        } else if (g.kind === "out") {
            line1 = u.short + " out in";
            line2 = g.big;
        } else if (g.kind === "warn") {
            line1 = u.short + " may run out";
            line2 = "by " + shortTime(bw.resetsAt, now);
        } else {
            line1 = u.short + " resets";
            line2 = bw.resetsAt !== null ? bw.key + " in " + duration(bw.resetsAt - now, true) : "—";
        }
        return { "rings": rings, "line1": line1, "line2": line2, "color": glanceColor(g.kind), "warn": warn, "opacity": stale ? 0.5 : 1 };
    }

    /** The popup's and tooltip's answer: { title: [{ t, c }], sub }. */
    readonly property var heroView: {
        const now = nowMs, T = textColor;
        if (pools.length === 0)
            return {
                "title": [{ "t": "Waiting for data…", "c": dimTextColor }],
                "sub": "No estimates from the daemon yet. They'll appear after its first poll."
            };
        const u = urgentPool(pools), g = glance(u, now), bw = g.bw, f = bw.forecast;
        const others = pools.filter(p => p !== u && p.block === null && p.verdict === "ok").map(p => p.label);
        const verb = others.length > 1 ? " are" : " is";
        const fine = others.length > 0 ? " " + others.join(" and ") + verb + " fine." : "";
        if (g.kind === "back")
            return {
                "title": [{ "t": u.label + " is out for ", "c": T }, { "t": g.big, "c": verdictColors.bad }, { "t": ".", "c": T }],
                "sub": "Back at " + longTime(u.block.until, now) + "."
                    + (others.length > 0 ? " " + others.join(" and ") + verb + " available meanwhile." : "")
            };
        if (g.kind === "out")
            return {
                "title": [{ "t": u.label + " runs out in ", "c": T }, { "t": g.big, "c": verdictColors.bad }, { "t": ".", "c": T }],
                "sub": "Around " + longTime(u.block.from, now) + ", back at " + longTime(u.block.until, now) + "." + fine
            };
        if (g.kind === "warn")
            return {
                "title": [{ "t": u.label + " might run out by ", "c": T }, { "t": longTime(bw.resetsAt, now), "c": verdictColors.warn }, { "t": ".", "c": T }],
                "sub": pct(f.pEmpty) + " chance on the " + bw.key + " window at " + pace(f) + " pace." + fine
            };
        const outs = [];
        for (const p of pools)
            for (const w of p.windows)
                if (w.out > 0 && w.resetsAt !== null)
                    outs.push(w.out + " of " + w.of + " " + p.label + " accounts out until " + shortTime(w.resetsAt, now) + ".");
        const summary = pools.map(p => {
            const b = bindingWindow(p);
            return p.label + " " + b.key + " at " + pct(b.used)
                + (b.resetsAt !== null ? ", resets in " + duration(b.resetsAt - now) : "") + ".";
        });
        return { "title": [{ "t": "All clear.", "c": T }], "sub": outs.concat(summary).join(" ") };
    }

    /** Run-outs, returns and resets from now on, sorted: [{ t, kind, title, detail }],
     *  kind "now", "out", "back", "risk" or "reset". */
    readonly property var events: {
        const now = nowMs;
        if (pools.length === 0)
            return [];
        const ev = [{
            "t": now, "kind": "now", "title": "Now",
            "detail": pools.map(p => p.label + " " + p.windows[0].key + " " + pct(p.windows[0].used)).join(" · ")
        }];
        for (const p of pools)
            for (const w of p.windows) {
                if (w.resetsAt === null)
                    continue;
                const f = w.forecast;
                if (w.state === "exhausted") {
                    ev.push({ "t": w.resetsAt, "kind": "back", "title": p.label + " back", "detail": w.key + " limit resets" });
                } else if (w.runsOut) {
                    const likely = w.outEarly !== null && w.outLate !== null ? " · likely " + hm(w.outEarly) + "–" + hm(w.outLate) : "";
                    ev.push({ "t": w.outAt, "kind": "out", "title": p.label + " runs out", "detail": w.key + likely + " · " + pace(f) + " pace" });
                    ev.push({ "t": w.resetsAt, "kind": "back", "title": p.label + " back", "detail": w.key + " resets" });
                } else if (w.verdict === "warn") {
                    if (w.outEarly !== null)
                        ev.push({ "t": w.outEarly, "kind": "risk", "title": p.label + " may run out", "detail": w.key + " · " + pct(f.pEmpty) + " chance, earliest now" });
                    ev.push({ "t": w.resetsAt, "kind": "reset", "title": p.label + " " + w.key + " resets", "detail": "lands around " + pct(Math.min(1, f.atReset.p50)) });
                } else {
                    ev.push({
                        "t": w.resetsAt, "kind": "reset", "title": p.label + " " + w.key + " resets",
                        "detail": (w.out > 0 ? w.out + "/" + w.of + " accounts back · " : "")
                            + "lands around " + pct(Math.min(1, f ? f.atReset.p50 : w.used)) + " · now " + pct(w.used)
                    });
                }
            }
        return ev.sort((a, b) => a.t - b.t);
    }

    function eventColor(kind) {
        return { "now": textColor, "out": verdictColors.bad, "back": verdictColors.ok, "risk": verdictColors.warn }[kind] || dimTextColor;
    }

    /** The popup agenda: event rows and a day row wherever the day changes. Each row carries
     *  its rail: pink while a pool is out, else a neutral line, ending at the last event.
     *  rows: { day, rail } | { event, railIn, railOut }. */
    readonly property var agendaRows: {
        const now = nowMs, ev = events, rows = [];
        const blocks = pools.filter(p => p.block !== null).map(p => p.block);
        const out = (a, b) => blocks.some(k => k.from <= a + 1 && k.until >= b - 1);
        let prevDay = null, rail = "transparent";
        ev.forEach((e, i) => {
            const dd = dayDelta(e.t, now);
            if (dd !== prevDay) {
                if (i > 0) {
                    const date = dayMonth(e.t);
                    rows.push({ "day": dd === 1 ? "Tomorrow" : (dd < 7 ? weekdays[new Date(e.t).getDay()] + " " + date : date), "rail": rail });
                }
                prevDay = dd;
            }
            const next = ev[i + 1];
            const railOut = next ? (out(e.t, next.t) ? verdictColors.bad : textAlpha(0.14)) : "transparent";
            rows.push({ "event": e, "railIn": i === 0 ? "transparent" : rail, "railOut": railOut });
            rail = railOut;
        });
        return rows;
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
    toolTipItem: Item {
        // The design's insets (border + padding) less the tooltip frame's own margins.
        readonly property real hPad: 11
        readonly property real vPad: 9
        implicitWidth: tip.width + 2 * hPad
        implicitHeight: tip.implicitHeight + 2 * vPad
        // The tooltip sizes itself from these, also when the content grows after it opened.
        Layout.minimumWidth: implicitWidth
        Layout.maximumWidth: implicitWidth
        Layout.minimumHeight: implicitHeight
        Layout.maximumHeight: implicitHeight

        TooltipContent {
            id: tip
            x: parent.hPad
            y: parent.vPad
            width: 280
        }
    }

    // Text sized in logical px, with the design's fixed line boxes and tabular figures.
    component Txt: PlasmaComponents3.Label {
        id: txt
        property real px: 14.67
        property real lh: 0
        // Lines as the browser lays them out: the baseline at the rounded ascent, plus half
        // the leading of a fixed line box (`lh`). Qt puts the baseline at the exact ascent
        // and all of a fixed line's leading below it, so shift the glyphs down, and pin the
        // height Qt would round up.
        readonly property real shift: Math.round(metrics.ascent) - metrics.ascent
            + (lh > 0 ? (lh - Math.round(metrics.ascent) - Math.round(metrics.descent)) / 2 : 0)
        height: lh > 0 ? lineCount * lh : implicitHeight
        Layout.preferredHeight: lh > 0 ? lineCount * lh : -1
        font.pointSize: root.pt(px)
        font.features: ({ "tnum": 1 })
        lineHeightMode: lh > 0 ? Text.FixedHeight : Text.ProportionalHeight
        lineHeight: lh > 0 ? lh : 1
        topPadding: shift
        bottomPadding: -shift
        readonly property alias fontMetrics: metrics
        FontMetrics {
            id: metrics
            font: txt.font
        }
    }

    // The tooltip: the popup's answer, then the next three events.
    component TooltipContent: ColumnLayout {
        id: tipContent
        readonly property var next: root.events.filter(e => e.kind !== "now").slice(0, 3)
        // One time column for every row, at least the design's 38 px.
        readonly property real timeWidth: Math.max(38, ...next.map(e => timeMetrics.advanceWidth(root.shortTime(e.t, root.nowMs))))
        spacing: 8

        FontMetrics {
            id: timeMetrics
            font.pointSize: root.pt(12)
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Txt {
                Layout.fillWidth: true
                px: 14
                lh: 19
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                textFormat: Text.StyledText
                text: root.styled(root.heroView.title)
            }
            Txt {
                Layout.fillWidth: true
                px: 12
                lh: 17
                wrapMode: Text.WordWrap
                color: root.dimTextColor
                text: root.heroView.sub
            }
        }
        Repeater {
            model: tipContent.next
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 10
                Txt {
                    Layout.preferredWidth: tipContent.timeWidth
                    px: 12
                    font.weight: Font.DemiBold
                    color: root.eventColor(parent.modelData.kind)
                    text: root.shortTime(parent.modelData.t, root.nowMs)
                }
                Txt {
                    Layout.fillWidth: true
                    px: 12
                    elide: Text.ElideRight
                    text: parent.modelData.title
                }
            }
        }
    }

    // A panel ring: how full the pool's binding window is.
    component Ring: Canvas {
        property real used: 0
        property color tone: root.textColor
        implicitWidth: 24
        implicitHeight: 24
        onUsedChanged: requestPaint()
        onToneChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.lineWidth = 2.5;
            ctx.strokeStyle = root.textAlpha(0.14);
            ctx.beginPath();
            ctx.arc(12, 12, 10, 0, 2 * Math.PI);
            ctx.stroke();
            if (used <= 0)
                return;
            ctx.strokeStyle = tone;
            ctx.beginPath();
            ctx.arc(12, 12, 10, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * used);
            ctx.stroke();
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
            const fg = root.textColor.toString();
            // 100 % ceiling.
            ctx.strokeStyle = fg;
            ctx.globalAlpha = 0.2;
            ctx.lineWidth = 1;
            ctx.setLineDash([2, 3]);
            ctx.beginPath();
            ctx.moveTo(0, 1);
            ctx.lineTo(w, 1);
            ctx.stroke();
            ctx.setLineDash([]);
            ctx.globalAlpha = 1;
            const win = chart.win;
            if (!win || win.start === null || win.resetsAt === null || w <= 0 || h <= 0)
                return;
            const now = Math.min(chart.now, win.resetsAt);
            // A pooled window can report a start after now; the axis then begins at now.
            const start = Math.min(win.start, now);
            const tx = t => w * (t - start) / (win.resetsAt - start);
            const uy = u => h - (h - 1.5) * Math.min(1, u);

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
                ctx.globalAlpha = 0.85;
                ctx.lineWidth = 1.3;
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
                ctx.lineWidth = 1.2;
                ctx.setLineDash([2.5, 5 / 3]);
                ctx.beginPath();
                ctx.moveTo(tx(now), uy(win.used));
                const mid = edge(f.emptyAt.p50, f.atReset.p50);
                ctx.lineTo(mid[0][0], mid[0][1]);
                ctx.stroke();
                ctx.setLineDash([]);
                ctx.globalAlpha = 1;
            }

            // The predicted outage, the only colour on the chart: from the median run-out
            // along the ceiling to the reset.
            if (win.runsOut && !chart.dimmed) {
                ctx.strokeStyle = root.verdictColors.bad;
                ctx.lineWidth = 2.5;
                ctx.beginPath();
                ctx.moveTo(tx(win.forecast.emptyAt.p50), uy(1) + 1.5);
                ctx.lineTo(w, uy(1) + 1.5);
                ctx.stroke();
            }
        }
    }

    compactRepresentation: MouseArea {
        id: compactRoot
        readonly property var view: root.panelView

        // The rings set the width; the text line takes the configured rest, and the user
        // widens it by dragging.
        Layout.minimumWidth: root.panelWidth
        Layout.preferredWidth: root.panelWidth
        onClicked: root.expanded = !root.expanded

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            spacing: 8
            opacity: compactRoot.view.opacity

            Row {
                Layout.alignment: Qt.AlignVCenter
                spacing: 4
                Repeater {
                    model: compactRoot.view.rings
                    delegate: Column {
                        required property var modelData
                        width: 32
                        spacing: 1
                        Item {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 24
                            height: 24
                            Ring {
                                anchors.fill: parent
                                used: modelData.used
                                tone: modelData.color
                            }
                            Txt {
                                anchors.centerIn: parent
                                px: 8.5
                                font.weight: Font.DemiBold
                                text: modelData.text
                            }
                        }
                        Txt {
                            anchors.horizontalCenter: parent.horizontalCenter
                            px: 9
                            lh: 10
                            color: root.dimTextColor
                            text: modelData.label
                        }
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                Txt {
                    Layout.fillWidth: true
                    px: 11
                    lh: 14
                    elide: Text.ElideRight
                    color: root.dimTextColor
                    text: compactRoot.view.line1
                }
                Txt {
                    Layout.fillWidth: true
                    px: 16
                    lh: 20
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    color: compactRoot.view.color
                    text: compactRoot.view.line2
                }
            }
            // Daemon trouble.
            Kirigami.Icon {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                visible: compactRoot.view.warn
                source: "data-warning"
            }
        }

        // Plasma gives panel applets no resize handles of their own (the stock Panel Spacer
        // only exposes a width in its config dialog), so provide one grip per edge. Dragging
        // away from the centre grows the text line, toward it shrinks — correct on either side
        // no matter which edge the panel layout happens to pin.
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
                    grip.pressWidth = root.textWidth;
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
                    root.dragTextWidth = Math.max(0, Math.round(grip.pressWidth + grip.sign * delta));
                }
                onReleased: {
                    if (grip.moved)
                        Plasmoid.configuration.textWidth = root.textWidth;
                    else
                        root.expanded = !root.expanded; // a plain click on the grip still toggles
                    root.dragTextWidth = -1;
                }
                onCanceled: root.dragTextWidth = -1

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
        // The design's insets (border + padding) less the Plasma dialog's own margins.
        readonly property real hPad: 13
        readonly property real topPad: 15
        readonly property real bottomPad: 13
        // Sized to the content: nothing scrolls and nothing stretches. One column until
        // there is data, then the agenda and the pools side by side.
        implicitWidth: (root.pools.length > 0 ? 2 * content.columnWidth + content.gutter : content.columnWidth) + 2 * hPad
        implicitHeight: content.implicitHeight + topPad + bottomPad
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: implicitWidth
        Layout.maximumWidth: implicitWidth
        Layout.minimumHeight: implicitHeight
        Layout.preferredHeight: implicitHeight
        Layout.maximumHeight: implicitHeight

        PopupContent {
            id: content
            x: parent.hPad
            y: parent.topPad
            width: parent.width - 2 * parent.hPad
        }
    }

    // A trouble line atop the popup: icon and text in one colour.
    component Notice: RowLayout {
        property alias icon: noticeIcon.source
        property alias text: noticeText.text
        property alias color: noticeText.color
        spacing: 8
        Kirigami.Icon {
            id: noticeIcon
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 16
            Layout.preferredHeight: 16
        }
        Txt {
            id: noticeText
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            px: 12
            wrapMode: Text.WordWrap
        }
    }

    // The popup: daemon trouble and the answer across the top, then the agenda on the left
    // and one section per pool on the right, each with a tile per window and a row per
    // account.
    component PopupContent: ColumnLayout {
        id: popup
        spacing: 18
        readonly property real dimmed: root.stale ? 0.55 : 1
        readonly property real columnWidth: 366
        // Between the columns: a hairline with this much room around it.
        readonly property real gutter: 33

        Notice {
            Layout.fillWidth: true
            visible: root.lastError !== ""
            icon: "dialog-error"
            color: root.verdictColors.bad
            text: root.lastError
        }
        Notice {
            Layout.fillWidth: true
            visible: root.unhealthy
            icon: "data-warning"
            color: root.verdictColors.warn
            text: (root.stale ? "Estimates are " + root.duration(root.nowMs - root.generatedAt) + " old"
                    : root.pollError !== "" ? "Last poll failed" : "Last history read failed")
                + " · the daemon isn't updating"
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            opacity: popup.dimmed
            Txt {
                id: heroTitle
                Layout.fillWidth: true
                px: 21
                lh: 27
                font.weight: Font.DemiBold
                font.letterSpacing: -0.21
                wrapMode: Text.WordWrap
                textFormat: Text.StyledText
                text: root.prettyStyled(root.heroView.title, heroTitle.fontMetrics, heroTitle.width)
            }
            Txt {
                id: heroSub
                Layout.fillWidth: true
                px: 13
                lh: 19
                wrapMode: Text.WordWrap
                textFormat: Text.StyledText
                text: root.prettyStyled([{ "t": root.heroView.sub, "c": root.dimTextColor }], heroSub.fontMetrics, heroSub.width)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.pools.length > 0
            spacing: 0

            // Agenda: time | rail and dot | what happens.
            Column {
                Layout.preferredWidth: popup.columnWidth
                Layout.alignment: Qt.AlignTop
                opacity: popup.dimmed
                readonly property real railX: 44 + 10 + 6
                readonly property real textX: 44 + 10 + 14 + 10

                Repeater {
                    model: root.agendaRows
                    delegate: Item {
                        id: agendaRow
                        required property var modelData
                        readonly property var ev: modelData.event || null
                        width: parent.width
                        height: ev ? evText.height + 12 : dayLabel.height + 14

                        // Day rows: the rail runs through, the date beside it.
                        Rectangle {
                            visible: !agendaRow.ev
                            x: agendaRow.parent.railX
                            width: 2
                            height: parent.height
                            color: agendaRow.modelData.rail || "transparent"
                        }
                        Txt {
                            id: dayLabel
                            visible: !agendaRow.ev
                            x: agendaRow.parent.textX
                            y: 8
                            px: 11
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.22
                            color: root.dimTextColor
                            text: agendaRow.modelData.day || ""
                        }

                        // Event rows.
                        Txt {
                            visible: !!agendaRow.ev
                            width: 44
                            px: 13
                            lh: 18
                            horizontalAlignment: Text.AlignRight
                            font.weight: Font.DemiBold
                            color: agendaRow.ev ? root.eventColor(agendaRow.ev.kind) : "transparent"
                            text: agendaRow.ev ? root.hm(agendaRow.ev.t) : ""
                        }
                        Rectangle {
                            visible: !!agendaRow.ev
                            x: agendaRow.parent.railX
                            width: 2
                            height: 9
                            color: agendaRow.modelData.railIn || "transparent"
                        }
                        Rectangle {
                            visible: !!agendaRow.ev
                            x: agendaRow.parent.railX
                            y: 9
                            width: 2
                            height: parent.height - 9
                            color: agendaRow.modelData.railOut || "transparent"
                        }
                        Rectangle {
                            readonly property string kind: agendaRow.ev ? agendaRow.ev.kind : ""
                            readonly property bool hollow: kind === "risk" || kind === "reset"
                            visible: !!agendaRow.ev
                            x: agendaRow.parent.railX - 4
                            y: 4
                            width: 10
                            height: 10
                            radius: 5
                            color: hollow ? Kirigami.Theme.backgroundColor : root.eventColor(kind)
                            border.width: 2
                            border.color: kind === "reset" ? root.textAlpha(0.45) : root.eventColor(kind)
                        }
                        Column {
                            id: evText
                            visible: !!agendaRow.ev
                            x: agendaRow.parent.textX
                            width: parent.width - x
                            Txt {
                                width: parent.width
                                px: 13.5
                                lh: 18
                                font.weight: Font.Medium
                                wrapMode: Text.WordWrap
                                text: agendaRow.ev ? agendaRow.ev.title : ""
                            }
                            Txt {
                                width: parent.width
                                px: 12
                                lh: 17
                                wrapMode: Text.WordWrap
                                color: root.dimTextColor
                                text: agendaRow.ev ? agendaRow.ev.detail : ""
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                Layout.leftMargin: (popup.gutter - 1) / 2
                Layout.rightMargin: (popup.gutter - 1) / 2
                color: root.textAlpha(0.1)
            }

            ColumnLayout {
                Layout.preferredWidth: popup.columnWidth
                Layout.alignment: Qt.AlignTop
                spacing: 18
                Repeater {
                    model: root.pools
                    delegate: PoolSection {
                        Layout.fillWidth: true
                        opacity: popup.dimmed
                    }
                }
            }
        }
    }

    // One pool in the popup: name and status, a tile per window, a row per account.
    component PoolSection: ColumnLayout {
        id: section
        required property var modelData
        required property int index
        readonly property var pool: modelData
        readonly property var status: root.poolStatus(pool, root.nowMs)
        readonly property bool shares: pool.accounts.some(a => a.share !== null)
        spacing: 8

        // Between pools; the column's top needs none.
        Rectangle {
            visible: section.index > 0
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.bottomMargin: 14 - section.spacing
            color: root.textAlpha(0.1)
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Txt {
                Layout.alignment: Qt.AlignBaseline
                px: 13
                font.weight: Font.DemiBold
                text: section.pool.label
            }
            Txt {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignBaseline
                px: 12
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                color: section.status[1]
                text: section.status[0]
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: section.pool.windows
                delegate: WindowTile {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    points: root.poolPoints(section.pool, modelData)
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 4
            Repeater {
                model: section.pool.accounts
                delegate: RowLayout {
                    id: acct
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10
                    Txt {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignBaseline
                        px: 12
                        elide: Text.ElideRight
                        color: root.dimTextColor
                        text: acct.modelData.name
                    }
                    Txt {
                        visible: section.shares
                        Layout.preferredWidth: 52
                        Layout.alignment: Qt.AlignBaseline
                        px: 12
                        horizontalAlignment: Text.AlignRight
                        color: root.dimTextColor
                        text: acct.modelData.share !== null ? root.pct(acct.modelData.share) + " cap" : "–"
                    }
                    Repeater {
                        model: section.pool.windows
                        delegate: Item {
                            id: cell
                            required property var modelData
                            readonly property var own: acct.modelData.windows.find(w => w.limit === modelData.limit) || null
                            readonly property bool out: own !== null && (own.state === "exhausted" || own.used >= 1)
                            Layout.preferredWidth: 56
                            Layout.preferredHeight: cellValue.height
                            Layout.alignment: Qt.AlignBaseline
                            baselineOffset: cellValue.baselineOffset
                            Row {
                                anchors.right: parent.right
                                Txt {
                                    anchors.baseline: cellValue.baseline
                                    px: 11
                                    color: root.dimTextColor
                                    text: cell.modelData.key + " "
                                }
                                Txt {
                                    id: cellValue
                                    px: 12
                                    font.weight: Font.Medium
                                    color: cell.out ? root.verdictColors.bad : root.textColor
                                    text: cell.own !== null ? root.pct(cell.own.used) : "–"
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // One window of a pool: share used, pace, burn chart and what comes next.
    component WindowTile: Rectangle {
        id: tile
        required property var modelData
        readonly property var win: modelData
        property var points: []
        readonly property var f: win.forecast
        implicitHeight: tileContent.implicitHeight + 9 + 10
        radius: 8
        color: root.textAlpha(0.05)

        ColumnLayout {
            id: tileContent
            x: 10
            y: 9
            width: parent.width - 20
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                Txt {
                    Layout.fillWidth: true
                    px: 11.5
                    font.weight: Font.DemiBold
                    color: root.dimTextColor
                    text: tile.win.key
                }
                Txt {
                    px: 11.5
                    color: root.dimTextColor
                    text: tile.f ? root.pace(tile.f) : ""
                }
            }
            Txt {
                px: 20
                lh: 24
                font.weight: Font.DemiBold
                color: tile.win.state === "exhausted" ? root.verdictColors.bad : root.textColor
                text: root.pct(tile.win.used)
            }
            BurnChart {
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                win: tile.win
                points: tile.points
                dimmed: root.stale
            }
            Txt {
                Layout.fillWidth: true
                px: 11.5
                elide: Text.ElideRight
                readonly property var w: tile.win
                color: w.state === "exhausted" || w.runsOut ? root.verdictColors.bad
                    : w.verdict === "warn" ? root.verdictColors.warn : root.dimTextColor
                text: {
                    if (w.resetsAt === null)
                        return w.state === "not_started" ? "not started" : "no data";
                    if (w.state === "exhausted")
                        return "back " + root.shortTime(w.resetsAt, root.nowMs);
                    if (w.runsOut)
                        return "out " + root.shortTime(w.outAt, root.nowMs) + " · back " + root.shortTime(w.resetsAt, root.nowMs);
                    return "resets " + root.shortTime(w.resetsAt, root.nowMs);
                }
            }
        }
    }
}
