import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Last good parse: array of { id, title, usedFraction, remainingPct, resetsAt, status }
    property var limits: []
    property double lastUpdated: 0
    property string lastError: ""
    property bool loading: false
    property bool everLoaded: false
    // Bumped by the countdown timer so formatEta() re-evaluates without a re-poll.
    property double nowMs: Date.now()

    readonly property string command: Plasmoid.configuration.command

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

    function windowTitle(title) {
        return title === "5h" ? "5 Hour window" : "7 Day window";
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
        // Merge all anthropic reports; worst (max usedFraction) per window id wins
        // so the display stays meaningful if multiple accounts ever appear.
        var byId = ({});
        for (var i = 0; i < reports.length; i++) {
            var rep = reports[i];
            if (rep.provider !== "anthropic")
                continue;
            var lims = rep.limits || [];
            for (var j = 0; j < lims.length; j++) {
                var lim = lims[j];
                if (lim.id !== "anthropic:5h" && lim.id !== "anthropic:7d")
                    continue;
                var amt = lim.amount || ({});
                var uf = (amt.usedFraction !== undefined && amt.usedFraction !== null)
                    ? amt.usedFraction
                    : ((amt.used || 0) / 100);
                var prev = byId[lim.id];
                if (prev === undefined || uf > prev.usedFraction) {
                    byId[lim.id] = {
                        "id": lim.id,
                        "title": (lim.window && lim.window.label === "5 Hour") ? "5h" : "7d",
                        "usedFraction": uf,
                        "remainingPct": Math.round(100 - 100 * uf),
                        "resetsAt": lim.window ? lim.window.resetsAt : undefined,
                        "status": lim.status || "unknown"
                    };
                }
            }
        }
        var out = [];
        var order = ["anthropic:5h", "anthropic:7d"];
        for (var k = 0; k < order.length; k++) {
            if (byId[order[k]] !== undefined)
                out.push(byId[order[k]]);
        }
        limits = out;
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
        if (limits.length === 0)
            return lastError !== "" ? lastError : "No Claude usage data";
        var lines = [];
        for (var i = 0; i < limits.length; i++) {
            var l = limits[i];
            var eta = formatEta(l.resetsAt, nowMs);
            var line = l.title + ": " + l.remainingPct + "% left";
            if (eta !== "")
                line += " · resets " + eta;
            lines.push(line);
        }
        return lines.join("\n");
    }

    compactRepresentation: MouseArea {
        id: compactRoot
        Layout.minimumWidth: Kirigami.Units.gridUnit * 4
        Layout.preferredWidth: Kirigami.Units.gridUnit * 6
        onClicked: root.expanded = !root.expanded

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.smallSpacing
            anchors.rightMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.mediumSpacing

            Item { Layout.fillHeight: true }

            Repeater {
                model: root.limits.length > 0 ? root.limits : [({})]
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
                        width: parent.width * (modelData && modelData.usedFraction !== undefined ? modelData.usedFraction : 0)
                        radius: parent.radius
                        color: (modelData && modelData.status !== undefined)
                            ? root.barColor(modelData.status, modelData.usedFraction)
                            : Kirigami.Theme.disabledTextColor
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        Layout.preferredHeight: Kirigami.Units.gridUnit * 12
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
            visible: root.limits.length === 0 && root.lastError === ""
            text: (root.loading && !root.everLoaded)
                ? "Loading…"
                : "No Claude usage data — run omp and /login"
        }

        Repeater {
            model: root.limits
            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents3.Label {
                        text: root.windowTitle(modelData.title)
                    }
                    Item { Layout.fillWidth: true }
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

        Item { Layout.fillHeight: true }

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
