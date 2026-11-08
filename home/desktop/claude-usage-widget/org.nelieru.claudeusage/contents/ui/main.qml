import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

// A thin renderer of the estimator daemon's view (`<estimator> get view --json`): every verdict,
// outage, pooled value and event comes from the daemon; this file only formats and lays out.
PlasmoidItem {
    id: root

    // The last view that parsed, null before the first one:
    //   { generatedAt, stale, error?, providers: [ProviderView], events: [ViewEvent] }
    // providers come most urgent first (`rank`), events sorted by time.
    property var view: null
    // Why the last `get view` failed, "" when it worked.
    property string lastError: ""

    readonly property string serverArg: {
        const s = Plasmoid.configuration.server.trim();
        return s === "" ? "" : " --server '" + s.replace(/'/g, "'\\''") + "'";
    }
    readonly property string viewCommand: Plasmoid.configuration.estimator + " get view --json" + serverArg

    /** "Now" for every relative time: the view's snapshot time. */
    readonly property double now: view !== null ? view.generatedAt : Date.now()
    readonly property var providers: view !== null ? (view.providers || []) : []
    readonly property var events: view !== null ? (view.events || []) : []
    readonly property bool stale: view !== null && view.stale === true
    readonly property string daemonError: view !== null && view.error ? view.error : ""
    readonly property bool trouble: stale || daemonError !== "" || lastError !== ""
    /** provider id -> ProviderView. */
    readonly property var providerById: {
        const m = {};
        for (const p of providers)
            m[p.provider] = p;
        return m;
    }
    /** The panel rings sorted by label, not urgency, so a ring never jumps to another slot. */
    readonly property var ringProviders: providers.slice().sort((a, b) => a.label.localeCompare(b.label))

    readonly property double minuteMs: 60000
    readonly property double dayMs: 86400000

    /** Bounds for the panel's text line, in px; the rings add 36 px per provider. Mirrored by
     *  the config spin box. */
    readonly property int minTextWidth: 0
    readonly property int maxTextWidth: 400
    /** >= 0 only while a resize grip is being dragged; overrides the stored width live so the
     *  drag stays smooth without writing config on every mouse move. */
    property int dragTextWidth: -1
    readonly property int textWidth: Math.max(minTextWidth, Math.min(maxTextWidth,
        dragTextWidth >= 0 ? dragTextWidth : Plasmoid.configuration.textWidth))
    readonly property int ringCount: ringProviders.length
    readonly property int panelWidth: 4 + (ringCount > 0 ? ringCount * 32 + (ringCount - 1) * 4 + 8 : 0) + textWidth + 4

    // Colours from the desktop's Monokai Pro Spectrum palette. Fixed rather than theme roles:
    // the stylix scheme maps neutralTextColor to cyan.
    readonly property color goodColor: "#7bd88f"
    readonly property color warnColor: "#fce566"
    readonly property color badColor: "#fc618d"
    readonly property color textColor: Kirigami.Theme.textColor
    // Secondary text. Opaque so it also works in Canvas and StyledText, and derived from the
    // text colour because the stylix scheme sets inactive/disabled text equal to normal text.
    readonly property color dimTextColor: Qt.tint(Kirigami.Theme.backgroundColor, textAlpha(0.75))
    readonly property var weekdays: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    readonly property var months: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    function textAlpha(a) {
        return Qt.rgba(textColor.r, textColor.g, textColor.b, a);
    }

    /** A provider status ("out", "runs_out", "warn", "ok") as a colour. */
    function statusColor(status) {
        return status === "out" || status === "runs_out" ? badColor : status === "warn" ? warnColor : textColor;
    }

    /** Point size of a font sized `px` logical pixels. */
    function pt(px) {
        return px * 0.75;
    }

    function present(v) {
        return v !== undefined && v !== null;
    }

    function pct(f) {
        return Math.round(f * 100) + "%";
    }

    /** 56.74, 12 or 0.5: at most two decimals. */
    function amount(x) {
        return String(Math.round(x * 100) / 100);
    }

    function pad2(n) {
        return n < 10 ? "0" + n : String(n);
    }

    function hm(t) {
        const d = new Date(t);
        return pad2(d.getHours()) + ":" + pad2(d.getMinutes());
    }

    /** Calendar days from the snapshot's day to `t`'s, in local time. */
    function dayDelta(t) {
        const a = new Date(t), b = new Date(now);
        const da = new Date(a.getFullYear(), a.getMonth(), a.getDate()).getTime();
        const db = new Date(b.getFullYear(), b.getMonth(), b.getDate()).getTime();
        return Math.round((da - db) / dayMs);
    }

    /** "12 Nov". */
    function dayMonth(t) {
        const d = new Date(t);
        return d.getDate() + " " + months[d.getMonth()];
    }

    /** "17:15" today, "Wed 16:00" within the week, else "12 Nov 16:00". */
    function shortTime(t) {
        const dd = dayDelta(t);
        if (dd === 0)
            return hm(t);
        if (dd > -7 && dd < 7)
            return weekdays[new Date(t).getDay()] + " " + hm(t);
        return dayMonth(t) + " " + hm(t);
    }

    /** As shortTime, with "tomorrow 16:00" for tomorrow. */
    function longTime(t) {
        return dayDelta(t) === 1 ? "tomorrow " + hm(t) : shortTime(t);
    }

    /** "Wed 18:00–23:00" within a day, else "Wed 18:00–Thu 04:00". */
    function span(a, b) {
        return shortTime(a) + "–" + (dayDelta(a) === dayDelta(b) ? hm(b) : shortTime(b));
    }

    /** Agenda day heading: "Tomorrow", "Wed 11 Nov" within the week, else "18 Nov". */
    function dayHeading(t) {
        const dd = dayDelta(t);
        if (dd === 1)
            return "Tomorrow";
        return dd > -7 && dd < 7 ? weekdays[new Date(t).getDay()] + " " + dayMonth(t) : dayMonth(t);
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

    /** "A", "A and B", "A, B and C". */
    function joinAnd(xs) {
        return xs.length < 2 ? xs.join("") : xs.slice(0, -1).join(", ") + " and " + xs[xs.length - 1];
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

    /** A provider's pool window by limit id, null when absent. */
    function windowOf(p, limit) {
        return p.windows.find(w => w.limit === limit) || null;
    }

    /** The window behind a provider's ring. */
    function ringWindow(p) {
        return windowOf(p, p.ring.limit);
    }

    /** "<label> 7d 54%": a provider's ring as text. */
    function ringSummary(p) {
        const w = ringWindow(p);
        return p.label + " " + (w !== null ? w.label + " " : "") + pct(p.ring.used);
    }

    /** One clause about a provider that is not ok: "<label> may run out (38%)". */
    function brief(p) {
        const o = p.outage;
        if (p.status === "out")
            return p.label + " is out" + (present(o.until) ? " until " + longTime(o.until) : "");
        if (p.status === "runs_out")
            return p.label + " runs out around " + longTime(o.from);
        return p.label + " may run out (" + pct(o.p) + ")";
    }

    /** Sentences about the providers besides the hero's. */
    function othersText(others) {
        const parts = others.filter(p => p.status !== "ok").map(p => brief(p) + ".");
        const fine = others.filter(p => p.status === "ok").map(p => p.label);
        if (fine.length > 0)
            parts.push(joinAnd(fine) + (fine.length > 1 ? " are" : " is") + " fine.");
        return parts.join(" ");
    }

    /** The popup's and tooltip's answer, about the most urgent provider: { title: [{ t, c }], sub }. */
    readonly property var heroView: {
        const T = textColor;
        if (view === null)
            return {
                "title": [{ "t": "Waiting for data…", "c": dimTextColor }],
                "sub": "No view from the estimator daemon yet."
            };
        if (providers.length === 0)
            return {
                "title": [{ "t": "Nothing to show.", "c": T }],
                "sub": "No provider has reported usage recently."
            };
        const p = providers[0], o = p.outage, others = othersText(providers.slice(1));
        const tail = others !== "" ? " " + others : "";
        if (p.status === "out")
            return {
                "title": present(o.until)
                    ? [{ "t": p.label + " is out until ", "c": T }, { "t": longTime(o.until), "c": badColor }, { "t": ".", "c": T }]
                    : [{ "t": p.label + " is ", "c": T }, { "t": "out", "c": badColor }, { "t": ".", "c": T }],
                "sub": (present(o.until) ? "Back in " + duration(o.until - now) + "." : "Not back within the forecast.")
                    + " Every account is blocked (" + o.windowLabel + ")." + tail
            };
        if (p.status === "runs_out")
            return {
                "title": [{ "t": p.label + " runs out in ", "c": T }, { "t": duration(o.from - now), "c": badColor }, { "t": ".", "c": T }],
                "sub": "Around " + longTime(o.from) + (present(o.until) ? ", back " + longTime(o.until) : "") + "."
                    + (o.p < 0.9 ? " " + pct(o.p) + " chance." : "") + tail
            };
        if (p.status === "warn")
            return {
                "title": [{ "t": p.label + " may run out (", "c": T }, { "t": pct(o.p) + " chance", "c": warnColor }, { "t": ").", "c": T }],
                "sub": "If it does, around " + longTime(o.from) + " on the " + o.windowLabel + " window"
                    + (present(o.until) ? ", back " + longTime(o.until) : "") + "." + tail
            };
        const lines = providers.map(q => {
            const w = ringWindow(q), out = q.accounts.filter(a => a.blocked).length;
            return ringSummary(q)
                + (w !== null && present(w.nextReset) ? ", resets in " + duration(w.nextReset - now) : "")
                + (out > 0 ? ", " + out + " of " + q.accounts.length + " accounts out" : "") + ".";
        });
        return { "title": [{ "t": "All providers fine.", "c": T }], "sub": lines.join(" ") };
    }

    /** The panel's two lines about the most urgent provider. */
    readonly property var panelView: {
        if (view === null)
            return { "line1": "Connecting…", "line2": "—", "color": dimTextColor };
        if (providers.length === 0)
            return { "line1": "No providers", "line2": "—", "color": dimTextColor };
        const p = providers[0], o = p.outage, c = statusColor(p.status);
        if (p.status === "out")
            return present(o.until)
                ? { "line1": p.short + " back in", "line2": duration(o.until - now), "color": c }
                : { "line1": p.short + " is", "line2": "out", "color": c };
        if (p.status === "runs_out")
            return { "line1": p.short + " out in", "line2": duration(o.from - now), "color": c };
        if (p.status === "warn")
            return { "line1": p.short + " may run out", "line2": pct(o.p) + " risk", "color": c };
        const w = ringWindow(p);
        return {
            "line1": w !== null ? "All fine · " + p.short + " " + w.label : "All fine",
            "line2": w !== null && present(w.nextReset) ? "resets " + duration(w.nextReset - now, true) : "—",
            "color": textColor
        };
    }

    /** A provider section's one-line status: [text, colour]. */
    function sectionStatus(p) {
        const o = p.outage;
        const until = o && present(o.until) ? " · back " + shortTime(o.until) : "";
        if (p.status === "out")
            return ["out" + until, badColor];
        if (p.status === "runs_out")
            return ["out " + shortTime(o.from) + until, badColor];
        if (p.status === "warn")
            return [pct(o.p) + " risk · around " + shortTime(o.from), warnColor];
        const w = ringWindow(p);
        return [ringSummary(p).slice(p.label.length + 1)
            + (w !== null && present(w.nextReset) ? " · resets in " + duration(w.nextReset - now) : ""), dimTextColor];
    }

    function eventColor(kind) {
        return ({
                "now": textColor,
                "pool_out": badColor,
                "pool_back": goodColor,
                "runs_out": warnColor,
                "back": textColor
            })[kind] || dimTextColor;
    }

    function eventTitle(e) {
        const p = providerById[e.provider], label = p ? p.label : e.provider;
        if (e.kind === "pool_out")
            return label + " runs out";
        if (e.kind === "pool_back")
            return label + " back";
        if (e.kind === "runs_out")
            return label + " account runs out";
        if (e.kind === "back")
            return label + " account back";
        return label + " " + e.windowLabel + " resets";
    }

    function eventDetail(e) {
        const p = providerById[e.provider], parts = [];
        if (present(e.account) && (e.kind !== "reset" || (p && p.accounts.length > 1)))
            parts.push(e.account);
        if (e.kind === "pool_out" || e.kind === "runs_out") {
            parts.push(e.windowLabel);
            if (present(e.early) && present(e.late))
                parts.push("likely " + span(e.early, e.late));
            if (present(e.until))
                parts.push("back " + shortTime(e.until));
        } else if (e.kind === "pool_back" || e.kind === "back") {
            parts.push(e.windowLabel + " resets");
        } else if (present(e.usedBefore)) {
            parts.push("from " + pct(e.usedBefore));
        }
        if (e.p < 0.9)
            parts.push(pct(e.p) + " chance");
        // A no-break space before each dot, so a wrapped line never starts with one.
        return parts.join("\u00a0· ");
    }

    /** The popup agenda: a Now row, the view's events and a day row wherever the day changes.
     *  The rail between rows is pink while a provider is out (yellow while only an unlikely
     *  outage is), following the view's pool_out/pool_back events.
     *  rows: { day, rail } | { event: { t, kind, title, detail }, railIn, railOut }. */
    readonly property var agendaRows: {
        if (view === null)
            return [];
        const open = {};
        for (const p of providers)
            if (p.status === "out")
                open[p.provider] = 1;
        const railColor = () => {
            const ps = Object.keys(open).map(k => open[k]);
            if (ps.length === 0)
                return textAlpha(0.14);
            return ps.some(x => x >= 0.5) ? badColor : warnColor;
        };
        const items = [{ "t": now, "kind": "now", "title": "Now", "detail": providers.map(ringSummary).join("\u00a0· ") }]
            .concat(events.map(e => ({ "t": e.t, "kind": e.kind, "provider": e.provider, "p": e.p, "title": eventTitle(e), "detail": eventDetail(e) })));
        const rows = [];
        let prevDay = 0, rail = "transparent";
        items.forEach((e, i) => {
            if (e.kind === "pool_out")
                open[e.provider] = e.p;
            else if (e.kind === "pool_back")
                delete open[e.provider];
            const dd = dayDelta(e.t);
            if (dd !== prevDay) {
                rows.push({ "day": dayHeading(e.t), "rail": rail });
                prevDay = dd;
            }
            const railOut = i < items.length - 1 ? railColor() : "transparent";
            rows.push({ "event": e, "railIn": i === 0 ? "transparent" : rail, "railOut": railOut });
            rail = railOut;
        });
        return rows;
    }

    function refresh() {
        if (exec.connectedSources.indexOf(root.viewCommand) === -1)
            exec.connectSource(root.viewCommand);
    }

    function handleView(exitCode, stdout, stderr) {
        if (exitCode !== 0) {
            lastError = (stderr && stderr.trim().length > 0) ? stderr.trim().split("\n")[0] : ("command exited " + exitCode);
            return;
        }
        let v;
        try {
            v = JSON.parse(stdout);
        } catch (e) {
            lastError = "parse error: " + e.message;
            return;
        }
        if (!v || typeof v.generatedAt !== "number" || !Array.isArray(v.providers)) {
            lastError = "unexpected view from the estimator";
            return;
        }
        view = v;
        lastError = "";
    }

    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            exec.disconnectSource(source);
            root.handleView(data["exit code"], data.stdout, data.stderr);
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

    onExpandedChanged: {
        if (root.expanded)
            refresh();
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
            width: 300
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
        // At least one line: an eliding label squeezed to no width reports no lines, and a
        // height of 0 would then keep it elided away for good.
        height: lh > 0 ? Math.max(1, lineCount) * lh : implicitHeight
        Layout.preferredHeight: lh > 0 ? Math.max(1, lineCount) * lh : -1
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
        readonly property var next: root.events.slice(0, 3)
        // One time column for every row, at least the design's 38 px.
        readonly property real timeWidth: Math.max(38, ...next.map(e => timeMetrics.advanceWidth(root.shortTime(e.t))))
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
                id: tipRow
                required property var modelData
                Layout.fillWidth: true
                spacing: 10
                Txt {
                    Layout.preferredWidth: tipContent.timeWidth
                    px: 12
                    font.weight: Font.DemiBold
                    color: root.eventColor(tipRow.modelData.kind)
                    text: root.shortTime(tipRow.modelData.t)
                }
                Txt {
                    Layout.fillWidth: true
                    px: 12
                    elide: Text.ElideRight
                    text: root.eventTitle(tipRow.modelData)
                }
            }
        }
    }

    // A panel ring: how full a provider's binding window is.
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
            ctx.arc(12, 12, 10, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.min(1, used));
            ctx.stroke();
        }
    }

    // A pool window's chart, y = 0 → 100 %: the view's pooled history as a neutral step curve
    // (pink once exhausted), then its forecast fan as a neutral p10–p90 band and a dashed
    // median, pink only where the median sits at 100 %.
    component Sparkline: Canvas {
        id: chart
        property var win: null
        property bool dimmed: false
        readonly property double now: root.now

        onWinChanged: requestPaint()
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
            if (!win || w <= 0 || h <= 0)
                return;
            const hist = win.history || [];
            const fan = win.fan && win.fan.t.length > 1 ? win.fan : null;
            const x0 = hist.length > 0 ? Math.min(hist[0][0], now) : now;
            const x1 = fan !== null ? fan.t[fan.t.length - 1]
                : (root.present(win.nextReset) && win.nextReset > now ? win.nextReset : now);
            if (x1 <= x0)
                return;
            const tx = t => w * (t - x0) / (x1 - x0);
            const uy = u => h - (h - 1.5) * Math.max(0, Math.min(1, u));

            if (hist.length > 0) {
                const path = () => {
                    let prev = hist[0][1];
                    ctx.moveTo(tx(hist[0][0]), uy(prev));
                    for (const p of hist.slice(1)) {
                        ctx.lineTo(tx(p[0]), uy(prev));
                        ctx.lineTo(tx(p[0]), uy(p[1]));
                        prev = p[1];
                    }
                    ctx.lineTo(tx(now), uy(prev));
                    ctx.lineTo(tx(now), uy(win.used));
                };
                const hc = chart.dimmed ? root.dimTextColor.toString()
                    : (win.state === "exhausted" ? root.badColor.toString() : fg);
                ctx.fillStyle = hc;
                ctx.globalAlpha = 0.16;
                ctx.beginPath();
                path();
                ctx.lineTo(tx(now), uy(0));
                ctx.lineTo(tx(hist[0][0]), uy(0));
                ctx.closePath();
                ctx.fill();
                ctx.strokeStyle = hc;
                ctx.globalAlpha = 0.85;
                ctx.lineWidth = 1.3;
                ctx.beginPath();
                path();
                ctx.stroke();
                ctx.globalAlpha = 1;
            }

            if (fan !== null) {
                const n = fan.t.length;
                ctx.fillStyle = fg;
                ctx.strokeStyle = fg;
                ctx.globalAlpha = 0.1;
                ctx.beginPath();
                ctx.moveTo(tx(fan.t[0]), uy(fan.p90[0]));
                for (let i = 1; i < n; i++)
                    ctx.lineTo(tx(fan.t[i]), uy(fan.p90[i]));
                for (let i = n - 1; i >= 0; i--)
                    ctx.lineTo(tx(fan.t[i]), uy(fan.p10[i]));
                ctx.closePath();
                ctx.fill();
                ctx.globalAlpha = 0.6;
                ctx.lineWidth = 1.2;
                ctx.setLineDash([2.5, 5 / 3]);
                ctx.beginPath();
                ctx.moveTo(tx(fan.t[0]), uy(fan.p50[0]));
                for (let i = 1; i < n; i++)
                    ctx.lineTo(tx(fan.t[i]), uy(fan.p50[i]));
                ctx.stroke();
                ctx.setLineDash([]);
                ctx.globalAlpha = 1;
                // Where the median forecast is full: the only colour on the chart.
                if (!chart.dimmed) {
                    ctx.strokeStyle = root.badColor.toString();
                    ctx.lineWidth = 2.5;
                    for (let i = 0; i < n - 1; i++)
                        if (fan.p50[i] >= 0.999 && fan.p50[i + 1] >= 0.999) {
                            ctx.beginPath();
                            ctx.moveTo(tx(fan.t[i]), uy(1) + 1.5);
                            ctx.lineTo(tx(fan.t[i + 1]), uy(1) + 1.5);
                            ctx.stroke();
                        }
                }
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
            opacity: root.stale ? 0.5 : 1

            Row {
                Layout.alignment: Qt.AlignVCenter
                Layout.minimumWidth: implicitWidth
                visible: root.ringCount > 0
                spacing: 4
                Repeater {
                    model: root.ringProviders
                    delegate: Column {
                        id: ring
                        required property var modelData
                        width: 32
                        spacing: 1
                        Item {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 24
                            height: 24
                            Ring {
                                anchors.fill: parent
                                used: ring.modelData.ring.used
                                tone: root.statusColor(ring.modelData.status)
                            }
                            Txt {
                                anchors.centerIn: parent
                                px: 8.5
                                font.weight: Font.DemiBold
                                text: String(Math.round(ring.modelData.ring.used * 100))
                            }
                        }
                        Txt {
                            width: parent.width
                            px: 9
                            lh: 10
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            color: root.dimTextColor
                            text: ring.modelData.short
                        }
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: root.textWidth
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
                visible: root.trouble
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
        id: full
        // The design's insets (border + padding) less the Plasma dialog's own margins.
        readonly property real hPad: 13
        readonly property real topPad: 15
        readonly property real bottomPad: 13
        // Sized to the content up to most of the screen's height; past that the agenda and
        // the provider sections scroll under the fixed answer.
        readonly property real maxHeight: Math.max(360, Screen.desktopAvailableHeight * 0.85)
        implicitWidth: content.outerWidth + 2 * hPad
        implicitHeight: Math.min(content.implicitHeight + topPad + bottomPad, maxHeight)
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: implicitWidth
        Layout.maximumWidth: implicitWidth
        Layout.minimumHeight: implicitHeight
        Layout.preferredHeight: implicitHeight
        Layout.maximumHeight: implicitHeight

        PopupContent {
            id: content
            x: full.hPad
            y: full.topPad
            width: full.width - 2 * full.hPad
            height: full.height - full.topPad - full.bottomPad
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

    // The popup: trouble and the answer across the top, then the agenda on the left and one
    // section per provider on the right, scrolling together when taller than the screen.
    component PopupContent: ColumnLayout {
        id: popup
        spacing: 18
        readonly property real dimmed: root.stale ? 0.55 : 1
        readonly property real agendaWidth: 366
        // Wider when a provider has many windows, so its tiles and account columns fit.
        readonly property real providersWidth: Math.max(366, 140 + 76 * Math.max(0, ...root.providers.map(p => p.windows.length)))
        // Between the columns: a hairline with this much room around it.
        readonly property real gutter: 33
        readonly property real bodyWidth: root.providers.length > 0 ? agendaWidth + gutter + providersWidth : agendaWidth
        // The agenda and provider sections, only once there is a provider to show.
        readonly property real bodyHeight: root.providers.length > 0 ? body.implicitHeight : 0
        readonly property bool scrolls: bodyHeight > flick.height + 1
        readonly property real outerWidth: bodyWidth + (scrolls ? 14 : 0)

        Notice {
            Layout.fillWidth: true
            visible: root.lastError !== ""
            icon: "dialog-error"
            color: root.badColor
            text: root.lastError + (root.view !== null ? " · showing the view of " + root.longTime(root.now) : "")
        }
        Notice {
            Layout.fillWidth: true
            visible: root.stale || root.daemonError !== ""
            icon: "data-warning"
            color: root.warnColor
            text: root.daemonError !== ""
                ? root.daemonError + (root.stale ? " · estimates may be outdated" : "")
                : "Estimates are " + root.duration(Date.now() - root.now) + " old · the daemon isn't updating"
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

        // Always in the layout, empty without providers: it takes up any height the popup has
        // to spare, which keeps the answer at the top.
        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: popup.bodyHeight
            Layout.minimumHeight: Math.min(popup.bodyHeight, 120)
            contentWidth: width
            contentHeight: popup.bodyHeight
            clip: popup.scrolls
            interactive: popup.scrolls
            boundsBehavior: Flickable.StopAtBounds
            QQC2.ScrollBar.vertical: PlasmaComponents3.ScrollBar {
                policy: popup.scrolls ? QQC2.ScrollBar.AlwaysOn : QQC2.ScrollBar.AlwaysOff
            }

            RowLayout {
                id: body
                visible: root.providers.length > 0
                width: popup.bodyWidth
                spacing: 0

                Agenda {
                    Layout.preferredWidth: popup.agendaWidth
                    Layout.alignment: Qt.AlignTop
                    opacity: popup.dimmed
                }

                Rectangle {
                    visible: root.providers.length > 0
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    Layout.leftMargin: (popup.gutter - 1) / 2
                    Layout.rightMargin: (popup.gutter - 1) / 2
                    color: root.textAlpha(0.1)
                }

                ColumnLayout {
                    visible: root.providers.length > 0
                    Layout.preferredWidth: popup.providersWidth
                    Layout.alignment: Qt.AlignTop
                    spacing: 18
                    Repeater {
                        model: root.providers
                        delegate: ProviderSection {
                            Layout.fillWidth: true
                            opacity: popup.dimmed
                        }
                    }
                }
            }
        }
    }

    // The agenda: time | rail and dot | what happens.
    component Agenda: Column {
        id: agenda
        readonly property real railX: 44 + 10 + 6
        readonly property real textX: 44 + 10 + 14 + 10

        Repeater {
            model: root.agendaRows
            delegate: Item {
                id: agendaRow
                required property var modelData
                readonly property var ev: modelData.event || null
                readonly property string kind: ev ? ev.kind : ""
                width: agenda.width
                height: ev ? evText.height + 12 : dayLabel.height + 14

                // Day rows: the rail runs through, the date beside it.
                Rectangle {
                    visible: !agendaRow.ev
                    x: agenda.railX
                    width: 2
                    height: parent.height
                    color: agendaRow.modelData.rail || "transparent"
                }
                Txt {
                    id: dayLabel
                    visible: !agendaRow.ev
                    x: agenda.textX
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
                    color: root.eventColor(agendaRow.kind)
                    text: agendaRow.ev ? root.hm(agendaRow.ev.t) : ""
                }
                Rectangle {
                    visible: !!agendaRow.ev
                    x: agenda.railX
                    width: 2
                    height: 9
                    color: agendaRow.modelData.railIn || "transparent"
                }
                Rectangle {
                    visible: !!agendaRow.ev
                    x: agenda.railX
                    y: 9
                    width: 2
                    height: parent.height - 9
                    color: agendaRow.modelData.railOut || "transparent"
                }
                Rectangle {
                    // Hollow for what may happen or changes little; filled for the rest.
                    readonly property bool hollow: agendaRow.kind === "runs_out" || agendaRow.kind === "reset"
                    visible: !!agendaRow.ev
                    x: agenda.railX - 4
                    y: 4
                    width: 10
                    height: 10
                    radius: 5
                    color: hollow ? Kirigami.Theme.backgroundColor
                        : agendaRow.kind === "back" ? root.textAlpha(0.7) : root.eventColor(agendaRow.kind)
                    border.width: 2
                    border.color: agendaRow.kind === "reset" ? root.textAlpha(0.45)
                        : agendaRow.kind === "back" ? root.textAlpha(0.7) : root.eventColor(agendaRow.kind)
                }
                Column {
                    id: evText
                    visible: !!agendaRow.ev
                    x: agenda.textX
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
                        visible: text !== ""
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

    // One provider in the popup: name and status, a tile per window, a row per account and a
    // line per balance.
    component ProviderSection: ColumnLayout {
        id: section
        required property var modelData
        required property int index
        readonly property var provider: modelData
        readonly property var status: root.sectionStatus(provider)
        readonly property var windows: provider.windows
        readonly property bool shares: provider.accounts.some(a => root.present(a.share))
        // Tiles at least this wide; rows balanced so no row is much shorter than another.
        readonly property real minTileWidth: 108
        readonly property int maxColumns: Math.max(1, Math.floor((width + 8) / (minTileWidth + 8)))
        readonly property int tileRows: Math.ceil(windows.length / maxColumns)
        readonly property int tileColumns: Math.max(1, Math.ceil(windows.length / Math.max(1, tileRows)))
        // The account table, flattened row by row for the grid: a header row of window labels,
        // then name | share | one cell per window.
        readonly property var cells: {
            const out = [{ "kind": "head", "text": "" }];
            if (shares)
                out.push({ "kind": "head", "text": "" });
            for (const w of windows)
                out.push({ "kind": "head", "text": w.label });
            for (const a of provider.accounts) {
                out.push({ "kind": "name", "text": a.account, "color": a.blocked ? root.badColor : root.dimTextColor });
                if (shares)
                    out.push({ "kind": "share", "text": root.present(a.share) ? root.pct(a.share) + " cap" : "–", "color": root.dimTextColor });
                for (const w of windows) {
                    const own = a.windows.find(x => x.limit === w.limit);
                    out.push({
                        "kind": "value",
                        "text": own ? root.pct(own.used) : "–",
                        "color": own && own.state === "exhausted" ? root.badColor : own ? root.textColor : root.dimTextColor
                    });
                }
            }
            return out;
        }
        spacing: 8

        // Between providers; the column's top needs none.
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
                text: section.provider.label
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
        GridLayout {
            Layout.fillWidth: true
            visible: section.windows.length > 0
            columns: section.tileColumns
            columnSpacing: 8
            rowSpacing: 8
            Repeater {
                model: section.windows
                delegate: WindowTile {
                    provider: section.provider
                    Layout.fillWidth: true
                    Layout.preferredWidth: (section.width - 8 * (section.tileColumns - 1)) / section.tileColumns
                    Layout.alignment: Qt.AlignTop
                }
            }
        }
        GridLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            visible: section.provider.accounts.length > 0
            columns: 1 + (section.shares ? 1 : 0) + section.windows.length
            columnSpacing: 12
            rowSpacing: 4
            Repeater {
                model: section.cells
                delegate: Txt {
                    id: cell
                    required property var modelData
                    readonly property bool isName: modelData.kind === "name"
                    readonly property bool isHead: modelData.kind === "head"
                    Layout.fillWidth: isName
                    Layout.preferredWidth: isName ? 60 : -1
                    Layout.maximumWidth: isHead ? 110 : -1
                    Layout.alignment: Qt.AlignBaseline | (isName ? Qt.AlignLeft : Qt.AlignRight)
                    px: isHead ? 11 : 12
                    font.weight: modelData.kind === "value" ? Font.Medium : Font.Normal
                    horizontalAlignment: isName ? Text.AlignLeft : Text.AlignRight
                    elide: Text.ElideRight
                    color: isHead ? root.dimTextColor : modelData.color
                    text: modelData.text
                }
            }
        }
        Repeater {
            model: section.provider.balances || []
            delegate: RowLayout {
                id: balance
                required property var modelData
                Layout.fillWidth: true
                spacing: 10
                Txt {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBaseline
                    px: 12
                    elide: Text.ElideRight
                    color: root.dimTextColor
                    text: balance.modelData.label
                        + (section.provider.accounts.length > 1 ? " · " + balance.modelData.account : "")
                }
                Txt {
                    Layout.alignment: Qt.AlignBaseline
                    px: 12
                    font.weight: Font.Medium
                    text: root.amount(balance.modelData.remaining) + " " + balance.modelData.unit
                }
            }
        }
    }

    // One pool window: pooled used, pace, chart and what comes next.
    component WindowTile: Rectangle {
        id: tile
        required property var modelData
        property var provider: null
        readonly property var win: modelData
        // The window the provider's outage binds on, when it has one.
        readonly property bool binding: provider !== null && provider.status !== "ok" && root.present(provider.outage)
            && provider.outage.limit === win.limit
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
                    elide: Text.ElideRight
                    color: root.dimTextColor
                    text: tile.win.label
                }
                Txt {
                    px: 11.5
                    color: root.dimTextColor
                    text: root.present(tile.win.pace) ? tile.win.pace.toFixed(1) + "×" : ""
                }
            }
            Txt {
                px: 20
                lh: 24
                font.weight: Font.DemiBold
                color: tile.win.state === "exhausted" ? root.badColor : root.textColor
                text: root.pct(tile.win.used)
            }
            Sparkline {
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                win: tile.win
                dimmed: root.stale
            }
            Txt {
                Layout.fillWidth: true
                px: 11.5
                elide: Text.ElideRight
                readonly property var w: tile.win
                readonly property var o: tile.binding ? tile.provider.outage : null
                color: o !== null ? root.statusColor(tile.provider.status)
                    : w.state === "exhausted" ? root.badColor : root.dimTextColor
                text: {
                    if (w.state === "no_data")
                        return "no data";
                    if (w.state === "not_started")
                        return "not started";
                    if (w.state === "expired")
                        return "expired";
                    const until = o !== null && root.present(o.until) ? "back " + root.shortTime(o.until) : "";
                    if (o !== null && tile.provider.status === "out")
                        return until !== "" ? until : "out";
                    if (o !== null && tile.provider.status === "runs_out")
                        return "out " + (root.present(o.until) ? root.span(o.from, o.until) : root.shortTime(o.from));
                    if (o !== null)
                        return root.pct(o.p) + " risk · " + root.shortTime(o.from);
                    const parts = [];
                    if (w.blocked > 0)
                        parts.push(w.blocked + "/" + w.accounts + " out");
                    if (root.present(w.nextReset))
                        parts.push("resets " + root.shortTime(w.nextReset));
                    if (parts.length < 2 && root.present(w.pEmpty) && w.pEmpty >= 0.05)
                        parts.push(root.pct(w.pEmpty) + " risk");
                    return parts.length > 0 ? parts.join(" · ") : "–";
                }
            }
        }
    }
}
