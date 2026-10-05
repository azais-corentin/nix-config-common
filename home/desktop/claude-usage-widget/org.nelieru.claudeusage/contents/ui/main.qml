import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Last good parse, sorted by provider then label:
    //   [{ key, provider, providerName, label, title, panelLabel, email, orgName, exhausted,
    //      limits: [{ id, title, windowId, usedFraction, remainingPct, resetsAt, status }] }]
    // `label` is the bare account name; `title` (popup, tooltip) and `panelLabel` (under
    // the panel bars) are qualified only as far as needed to tell accounts apart.
    // `exhausted` is true when the 5h or 7d window is used up: the account is blocked, so
    // every one of its bars turns red.
    property var accounts: []
    property double lastUpdated: 0
    property string lastError: ""
    property bool loading: false
    property bool everLoaded: false
    // Bumped by the countdown timer so formatEta() re-evaluates without a re-poll.
    property double nowMs: Date.now()

    readonly property string command: Plasmoid.configuration.command

    // Providers the widget renders; every other report in the omp output is ignored.
    // panelIds are the two shared (non-tier) windows per provider: tier windows such as
    // anthropic:7d:fable or openai-codex:spark:primary share a windowId with them, so
    // matching has to go by exact id.
    readonly property var providers: ({
        "anthropic": { "name": "Claude", "panelIds": ["anthropic:5h", "anthropic:7d"] },
        "openai-codex": { "name": "Codex", "panelIds": ["openai-codex:primary", "openai-codex:secondary"] }
    })
    // Fixed panel rows. Codex's primary window is 5h or 7d depending on the plan, so rows
    // are keyed by window rather than by limit id.
    readonly property var panelWindows: ["5h", "7d"]

    /** Bounds for the in-panel width, in px. Mirrored by the config spin box. */
    readonly property int minPanelWidth: 48
    readonly property int maxPanelWidth: 600
    /** >= 0 only while a resize grip is being dragged; overrides the stored width live so the
     *  drag stays smooth without writing config on every mouse move. */
    property int dragWidth: -1
    readonly property int effectiveWidth: Math.max(minPanelWidth, Math.min(maxPanelWidth,
        dragWidth >= 0 ? dragWidth : Plasmoid.configuration.panelWidth))

    // Bar fill: solid green up to gradientStart, then green → yellow → orange → red at 100%.
    // Fixed Breeze-derived colours rather than theme roles: the stylix scheme maps
    // neutralTextColor to cyan. Stops are mixed in OKLCH because straight RGB/OKLab mixes
    // between distant hues pass through desaturated olive and salmon.
    readonly property real gradientStart: 0.8
    readonly property var gradientHex: ["#27ae60", "#fdbc4b", "#f67400", "#e0362a"]
    readonly property var gradientStops: gradientHex.map(hexToOklch)

    function srgbToLinear(c) {
        return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    }

    function linearToSrgb(c) {
        var v = c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055;
        return Math.max(0, Math.min(1, v));
    }

    function hexToOklch(hex) {
        var r = srgbToLinear(parseInt(hex.substr(1, 2), 16) / 255);
        var g = srgbToLinear(parseInt(hex.substr(3, 2), 16) / 255);
        var b = srgbToLinear(parseInt(hex.substr(5, 2), 16) / 255);
        var l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
        var m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
        var s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
        var labA = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
        var labB = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
        return {
            "L": 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            "C": Math.hypot(labA, labB),
            "h": Math.atan2(labB, labA)
        };
    }

    function oklchToColor(L, C, h) {
        var labA = C * Math.cos(h);
        var labB = C * Math.sin(h);
        var l = Math.pow(L + 0.3963377774 * labA + 0.2158037573 * labB, 3);
        var m = Math.pow(L - 0.1055613458 * labA - 0.0638541728 * labB, 3);
        var s = Math.pow(L - 0.0894841775 * labA - 1.2914855480 * labB, 3);
        return Qt.rgba(linearToSrgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                       linearToSrgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                       linearToSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s),
                       1);
    }

    function barColor(usedFraction, exhausted) {
        var stops = gradientStops;
        var last = stops.length - 1;
        if (exhausted)
            return gradientHex[last];
        var t = (usedFraction - gradientStart) / (1 - gradientStart);
        t = Math.max(0, Math.min(1, t)) * last;
        var i = Math.min(Math.floor(t), last - 1);
        var f = t - i;
        var a = stops[i];
        var b = stops[i + 1];
        // Shortest way round the hue circle.
        var dh = b.h - a.h;
        if (dh > Math.PI)
            dh -= 2 * Math.PI;
        else if (dh < -Math.PI)
            dh += 2 * Math.PI;
        return oklchToColor(a.L + (b.L - a.L) * f, a.C + (b.C - a.C) * f, a.h + dh * f);
    }

    function isExhausted(limit) {
        return limit !== null && (limit.status === "exhausted" || limit.usedFraction >= 1);
    }

    function formatEta(resetsAt, now) {
        if (resetsAt === undefined || resetsAt === null)
            return "";
        var diff = resetsAt - now;
        if (diff <= 0)
            return "";
        var mins = Math.floor(diff / 60000);
        var days = Math.floor(mins / 1440);
        mins -= days * 1440;
        var hours = Math.floor(mins / 60);
        mins -= hours * 60;
        if (days > 0)
            return "in " + days + "d " + hours + "h";
        if (hours > 0)
            return "in " + hours + "h " + mins + "m";
        return "in " + mins + "m";
    }

    function accountKey(provider, meta, idx) {
        if (meta && meta.accountId)
            return provider + ":" + meta.accountId;
        if (meta && meta.email)
            return provider + ":" + meta.email;
        return provider + ":report:" + idx;
    }

    function accountLabel(meta, idx) {
        var email = (meta && meta.email) ? String(meta.email) : "";
        if (email !== "") {
            var at = email.indexOf("@");
            return at > 0 ? email.substring(0, at) : email;
        }
        if (meta && meta.accountId)
            return String(meta.accountId).substring(0, 8);
        return "account " + (idx + 1);
    }

    // Qualify with the provider only when several are present, and with the account name
    // only when that provider has several accounts: "Claude alice", "Claude bob", "Codex".
    function accountTitle(acct, multiProvider, perProvider) {
        var parts = [];
        if (multiProvider)
            parts.push(acct.providerName);
        if (perProvider[acct.provider] > 1 || !multiProvider)
            parts.push(acct.label);
        return parts.join(" ");
    }

    // Panel columns are a few dozen px wide and elide from the right, so lead with the one
    // word that separates this column from its neighbours: "alice", "bob", "Codex".
    function accountPanelLabel(acct, multiProvider, perProvider) {
        return (multiProvider && perProvider[acct.provider] === 1) ? acct.providerName : acct.label;
    }

    // One entry per panelWindows row, in order; null renders an empty track so columns
    // stay aligned when an account lacks a window.
    function panelLimits(account) {
        var ids = providers[account.provider].panelIds;
        var out = [];
        for (var w = 0; w < panelWindows.length; w++) {
            var found = null;
            for (var i = 0; i < account.limits.length; i++) {
                var lim = account.limits[i];
                if (ids.indexOf(lim.id) !== -1 && lim.windowId === panelWindows[w]) {
                    found = lim;
                    break;
                }
            }
            out.push(found);
        }
        return out;
    }

    function refresh() {
        loading = true;
        if (exec.connectedSources.indexOf(root.command) === -1)
            exec.connectSource(root.command);
    }

    function handle(exitCode, stdout, stderr) {
        loading = false;
        everLoaded = true;
        if (exitCode !== 0) {
            var msg = (stderr && stderr.trim().length > 0)
                ? stderr.trim().split("\n")[0]
                : ("command exited " + exitCode);
            lastError = msg;
            return;
        }
        var parsed;
        try {
            parsed = JSON.parse(stdout);
        } catch (e) {
            lastError = "parse error: " + e.message;
            return;
        }
        var reports = (parsed && parsed.reports) || [];
        var out = [];
        var perProvider = ({});
        for (var i = 0; i < reports.length; i++) {
            var rep = reports[i];
            var info = providers[rep.provider];
            if (info === undefined)
                continue;
            var meta = rep.metadata || ({});
            var lims = rep.limits || [];
            var norm = [];
            for (var j = 0; j < lims.length; j++) {
                var lim = lims[j];
                var amt = lim.amount || ({});
                var uf = (amt.usedFraction !== undefined && amt.usedFraction !== null)
                    ? amt.usedFraction
                    : ((amt.used || 0) / 100);
                norm.push({
                    "id": lim.id,
                    // "Claude 7 Day (Fable)" -> "7 Day (Fable)"; the provider is already
                    // implied by the account header, and the popup is only ~18 grid units wide.
                    "title": String(lim.label || lim.id).replace(/^Claude\s+/, ""),
                    "windowId": lim.window ? lim.window.id : (lim.scope ? lim.scope.windowId : undefined),
                    "usedFraction": uf,
                    "remainingPct": Math.round(100 - 100 * uf),
                    "resetsAt": lim.window ? lim.window.resetsAt : undefined,
                    "status": lim.status || "unknown"
                });
            }
            perProvider[rep.provider] = (perProvider[rep.provider] || 0) + 1;
            out.push({
                "key": accountKey(rep.provider, meta, i),
                "provider": rep.provider,
                "providerName": info.name,
                "label": accountLabel(meta, i),
                "email": (meta.email !== undefined && meta.email !== null) ? String(meta.email) : "",
                "orgName": (meta.orgName !== undefined && meta.orgName !== null) ? String(meta.orgName) : "",
                "limits": norm
            });
        }
        var multiProvider = Object.keys(perProvider).length > 1;
        for (var k = 0; k < out.length; k++) {
            out[k].title = accountTitle(out[k], multiProvider, perProvider);
            out[k].panelLabel = accountPanelLabel(out[k], multiProvider, perProvider);
            out[k].exhausted = panelLimits(out[k]).some(isExhausted);
        }
        // Stable ordering: omp's report order is not guaranteed, and usage-based sorting
        // would make columns swap places between polls.
        out.sort(function (a, b) {
            if (a.providerName !== b.providerName)
                return a.providerName < b.providerName ? -1 : 1;
            if (a.label !== b.label)
                return a.label < b.label ? -1 : 1;
            if (a.email !== b.email)
                return a.email < b.email ? -1 : 1;
            return a.key < b.key ? -1 : (a.key > b.key ? 1 : 0);
        });
        accounts = out;
        lastError = "";
        lastUpdated = (parsed && parsed.generatedAt) ? parsed.generatedAt : Date.now();
        nowMs = Date.now();
    }

    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            exec.disconnectSource(source);
            root.handle(data["exit code"], data.stdout, data.stderr);
        }
    }

    // Poll the CLI. triggeredOnStart gives an immediate first read.
    Timer {
        interval: Math.max(15, Plasmoid.configuration.pollIntervalSeconds) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Refresh only the countdown strings between polls.
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.nowMs = Date.now()
    }

    onExpandedChanged: if (expanded) refresh()

    toolTipMainText: "AI Usage"
    toolTipSubText: {
        if (accounts.length === 0)
            return lastError !== "" ? lastError : "No Claude or Codex usage data";
        var lines = [];
        for (var i = 0; i < accounts.length; i++) {
            var acct = accounts[i];
            if (accounts.length > 1)
                lines.push(acct.title);
            var rows = panelLimits(acct);
            for (var j = 0; j < rows.length; j++) {
                var l = rows[j];
                if (l === null)
                    continue;
                var eta = formatEta(l.resetsAt, nowMs);
                var line = l.windowId + ": " + l.remainingPct + "% left";
                if (eta !== "")
                    line += " · resets " + eta;
                lines.push(accounts.length > 1 ? "  " + line : line);
            }
        }
        return lines.join("\n");
    }

    // Rounded usage bar shared by panel and popup. Track keyed off the text color so it
    // stays visible on both light and dark backgrounds (background-derived tracks vanish
    // against the panel).
    component UsageBar: Rectangle {
        id: bar
        property real fraction: 0
        property color fillColor: Kirigami.Theme.disabledTextColor
        radius: height / 2
        color: Qt.rgba(Kirigami.Theme.textColor.r,
                       Kirigami.Theme.textColor.g,
                       Kirigami.Theme.textColor.b, 0.25)

        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            width: parent.width * Math.max(0, Math.min(1, bar.fraction))
            radius: parent.radius
            color: bar.fillColor
        }
    }

    compactRepresentation: MouseArea {
        id: compactRoot
        // One entry per account; a single null column keeps the placeholder bars
        // visible before the first successful poll.
        readonly property var columns: root.accounts.length > 0 ? root.accounts : [null]
        // Labels only matter when there is something to disambiguate, and only if
        // the panel is tall enough to fit a line of text under the bars.
        readonly property bool showLabels: root.accounts.length > 1
            && compactRoot.height >= Kirigami.Units.gridUnit * 2

        // The configured width wins over any account-count heuristic: columns share
        // whatever room it gives them, and the user widens the widget by dragging.
        Layout.minimumWidth: root.effectiveWidth
        Layout.preferredWidth: root.effectiveWidth
        onClicked: root.expanded = !root.expanded

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.smallSpacing
            anchors.rightMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: compactRoot.columns
                delegate: ColumnLayout {
                    id: accountColumn
                    required property var modelData
                    readonly property var account: modelData
                    Layout.fillWidth: true
                    // Every account gets the same slice of the panel: without a fixed
                    // preferred width the column inherits the label's text width, so a
                    // longer account name would claim more room than a short one. The
                    // label elides instead.
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    spacing: Kirigami.Units.mediumSpacing

                    Item { Layout.fillHeight: true }

                    Repeater {
                        // Always two rows so every column lines up, even when an
                        // account is missing one of the shared windows.
                        model: accountColumn.account
                            ? root.panelLimits(accountColumn.account)
                            : [null, null]
                        delegate: UsageBar {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 5
                            fraction: modelData ? modelData.usedFraction : 0
                            fillColor: modelData
                                ? root.barColor(modelData.usedFraction, accountColumn.account.exhausted)
                                : Kirigami.Theme.disabledTextColor
                        }
                    }

                    PlasmaComponents3.Label {
                        visible: compactRoot.showLabels
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        opacity: 0.8
                        font: Kirigami.Theme.smallFont
                        text: accountColumn.account ? accountColumn.account.panelLabel : ""
                    }

                    Item { Layout.fillHeight: true }
                }
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

    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 18
        Layout.preferredHeight: Kirigami.Units.gridUnit * 22
        spacing: Kirigami.Units.smallSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Error
            visible: root.lastError !== ""
            text: root.lastError
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: root.accounts.length === 0 && root.lastError === ""
            text: (root.loading && !root.everLoaded)
                ? "Loading…"
                : "No Claude or Codex usage data — run omp and /login"
        }

        PlasmaComponents3.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.accounts.length > 0

            ListView {
                model: root.accounts
                spacing: Kirigami.Units.largeSpacing
                clip: true

                delegate: ColumnLayout {
                    id: accountSection
                    required property var modelData
                    required property int index
                    width: ListView.view ? ListView.view.width : 0
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Separator {
                        Layout.fillWidth: true
                        visible: accountSection.index > 0
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        // A header adds nothing when there is only one account.
                        visible: root.accounts.length > 1

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.bold: true
                            text: accountSection.modelData.title
                        }
                    }

                    Repeater {
                        // Every limit the report carries, tier windows included.
                        model: accountSection.modelData.limits
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: modelData.title
                                }
                                PlasmaComponents3.Label {
                                    text: modelData.remainingPct + "% left"
                                    font.bold: true
                                }
                            }

                            UsageBar {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 6
                                fraction: modelData.usedFraction
                                fillColor: root.barColor(modelData.usedFraction, accountSection.modelData.exhausted)
                            }

                            PlasmaComponents3.Label {
                                readonly property string eta: root.formatEta(modelData.resetsAt, root.nowMs)
                                visible: eta !== ""
                                text: "resets " + eta
                                opacity: 0.7
                                font: Kirigami.Theme.smallFont
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents3.Label {
                visible: root.lastUpdated > 0
                text: "updated " + new Date(root.lastUpdated).toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
                opacity: 0.7
                font: Kirigami.Theme.smallFont
            }
            Item { Layout.fillWidth: true }
            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh"
                onClicked: root.refresh()
            }
        }
    }
}
