import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Last good parse, sorted by label:
    //   [{ key, label, email, orgName, limits: [{ id, title, usedFraction,
    //                                             remainingPct, resetsAt, status }] }]
    property var accounts: []
    property double lastUpdated: 0
    property string lastError: ""
    property bool loading: false
    property bool everLoaded: false
    // Bumped by the countdown timer so formatEta() re-evaluates without a re-poll.
    property double nowMs: Date.now()

    readonly property string command: Plasmoid.configuration.command

    /** Bounds for the in-panel width, in px. Mirrored by the config spin box. */
    readonly property int minPanelWidth: 48
    readonly property int maxPanelWidth: 600
    /** >= 0 only while a resize grip is being dragged; overrides the stored width live so the
     *  drag stays smooth without writing config on every mouse move. */
    property int dragWidth: -1
    readonly property int effectiveWidth: Math.max(minPanelWidth, Math.min(maxPanelWidth,
        dragWidth >= 0 ? dragWidth : Plasmoid.configuration.panelWidth))

    function barColor(status, usedFraction) {
        if (status === "exhausted" || usedFraction >= 1)
            return Kirigami.Theme.negativeTextColor;
        if (status === "warning" || usedFraction >= 0.9)
            return Kirigami.Theme.neutralTextColor;
        return Kirigami.Theme.positiveTextColor;
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

    function accountKey(meta, idx) {
        if (meta && meta.accountId)
            return String(meta.accountId);
        if (meta && meta.email)
            return String(meta.email);
        return "report:" + idx;
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

    // Panel bars are the two shared windows, in fixed order. Exact ids on purpose:
    // scope.windowId is "7d" for both anthropic:7d and anthropic:7d:fable.
    function panelLimits(account) {
        var wanted = ["anthropic:5h", "anthropic:7d"];
        var out = [];
        for (var w = 0; w < wanted.length; w++) {
            var found = null;
            for (var i = 0; i < account.limits.length; i++) {
                if (account.limits[i].id === wanted[w]) {
                    found = account.limits[i];
                    break;
                }
            }
            out.push(found);   // null => render an empty track so columns stay aligned
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
        for (var i = 0; i < reports.length; i++) {
            var rep = reports[i];
            if (rep.provider !== "anthropic")
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
                    // implied by the widget, and the popup is only ~18 grid units wide.
                    "title": String(lim.label || lim.id).replace(/^Claude\s+/, ""),
                    "usedFraction": uf,
                    "remainingPct": Math.round(100 - 100 * uf),
                    "resetsAt": lim.window ? lim.window.resetsAt : undefined,
                    "status": lim.status || "unknown"
                });
            }
            out.push({
                "key": accountKey(meta, i),
                "label": accountLabel(meta, i),
                "email": (meta.email !== undefined && meta.email !== null) ? String(meta.email) : "",
                "orgName": (meta.orgName !== undefined && meta.orgName !== null) ? String(meta.orgName) : "",
                "limits": norm
            });
        }
        // Stable ordering: omp's report order is not guaranteed, and usage-based sorting
        // would make columns swap places between polls.
        out.sort(function (a, b) {
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

    toolTipMainText: "Claude Usage"
    toolTipSubText: {
        if (accounts.length === 0)
            return lastError !== "" ? lastError : "No Claude usage data";
        var lines = [];
        for (var i = 0; i < accounts.length; i++) {
            var acct = accounts[i];
            if (accounts.length > 1)
                lines.push(acct.label);
            var rows = panelLimits(acct);
            for (var j = 0; j < rows.length; j++) {
                var l = rows[j];
                if (l === null)
                    continue;
                var eta = formatEta(l.resetsAt, nowMs);
                var short = (l.id === "anthropic:5h") ? "5h" : "7d";
                var line = short + ": " + l.remainingPct + "% left";
                if (eta !== "")
                    line += " · resets " + eta;
                lines.push(accounts.length > 1 ? "  " + line : line);
            }
        }
        return lines.join("\n");
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
                    Layout.fillHeight: true
                    spacing: Kirigami.Units.mediumSpacing

                    Item { Layout.fillHeight: true }

                    Repeater {
                        // Always two rows so every column lines up, even when an
                        // account is missing one of the shared windows.
                        model: accountColumn.account
                            ? root.panelLimits(accountColumn.account)
                            : [null, null]
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 5
                            radius: height / 2
                            // Track keyed off the panel text color so it stays visible
                            // on both light and dark panels (background-derived tracks
                            // vanish against the panel).
                            color: Qt.rgba(Kirigami.Theme.textColor.r,
                                           Kirigami.Theme.textColor.g,
                                           Kirigami.Theme.textColor.b, 0.25)

                            Rectangle {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                height: parent.height
                                width: parent.width * (modelData ? modelData.usedFraction : 0)
                                radius: parent.radius
                                color: modelData
                                    ? root.barColor(modelData.status, modelData.usedFraction)
                                    : Kirigami.Theme.disabledTextColor
                            }
                        }
                    }

                    PlasmaComponents3.Label {
                        visible: compactRoot.showLabels
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        opacity: 0.8
                        font: Kirigami.Theme.smallFont
                        text: accountColumn.account ? accountColumn.account.label : ""
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
                : "No Claude usage data — run omp and /login"
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
                            text: accountSection.modelData.label
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

                            PlasmaComponents3.ProgressBar {
                                Layout.fillWidth: true
                                from: 0
                                to: 1
                                value: modelData.usedFraction
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
