import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Last parsed output of fetch_usage.py; keeps the previous usage when a fetch fails.
    property var result: null
    readonly property var usage: result ? result.usage : null
    readonly property bool stale: !result || !result.ok
    property bool busy: false
    property double busySince: 0
    property double now: Date.now()
    // Poll-interval multiplier, doubled on HTTP 429.
    property int backoff: 1
    property int skipTicks: 0

    readonly property var sessionLimit: findLimit("session")
    readonly property var weeklyLimit: findLimit("weekly")
    readonly property var centerLimit: {
        switch (Plasmoid.configuration.centerValue) {
        case "weekly": return weeklyLimit;
        case "max": return maxLimit();
        default: return sessionLimit;
        }
    }

    readonly property string scriptPath: decodeURIComponent(Qt.resolvedUrl("../code/fetch_usage.py").toString().replace(/^file:\/\//, ""))

    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    function command() {
        let cmd = "python3 " + shellQuote(scriptPath);
        if (Plasmoid.configuration.credentialsPath)
            cmd += " " + shellQuote(Plasmoid.configuration.credentialsPath);
        return cmd;
    }

    function refresh() {
        if (busy && Date.now() - busySince < 60000)
            return;
        const cmd = command();
        exec.disconnectSource(cmd); // the engine ignores connectSource for an already connected source
        busy = true;
        busySince = Date.now();
        exec.connectSource(cmd);
    }

    function findLimit(group) {
        if (!usage)
            return null;
        let best = null;
        for (const l of usage.limits) {
            if (l.group !== group)
                continue;
            if (l.kind === "weekly_all")
                return l;
            if (!best || l.percent > best.percent)
                best = l;
        }
        return best;
    }

    function maxLimit() {
        if (!usage)
            return null;
        let best = null;
        for (const l of usage.limits)
            if (!best || effectivePercent(l) > effectivePercent(best))
                best = l;
        return best;
    }

    // A window whose reset time has passed is back to 0%, even if our data is older.
    function effectivePercent(l) {
        if (!l)
            return 0;
        if (l.resetsAt && l.resetsAt <= root.now)
            return 0;
        return Math.max(0, Math.min(100, l.percent));
    }

    function colorFor(pct) {
        if (pct >= 90)
            return Kirigami.Theme.negativeTextColor;
        if (pct >= 75)
            return Kirigami.Theme.neutralTextColor;
        return Kirigami.Theme.highlightColor;
    }

    function fmtDuration(msLeft) {
        const m = Math.max(0, Math.round(msLeft / 60000));
        const d = Math.floor(m / 1440), h = Math.floor(m % 1440 / 60), mm = m % 60;
        if (d > 0)
            return d + "d " + h + "h";
        if (h > 0)
            return h + "h " + mm + "m";
        return mm + "m";
    }

    function fmtClock(t) {
        const d = new Date(t);
        if (d.toDateString() === new Date(root.now).toDateString())
            return Qt.formatTime(d, "HH:mm");
        return Qt.formatDateTime(d, "ddd d MMM, HH:mm");
    }

    function resetText(l) {
        if (!l || !l.resetsAt)
            return "";
        if (l.resetsAt <= root.now)
            return i18n("Reset at %1", fmtClock(l.resetsAt));
        return i18n("Resets in %1 (%2)", fmtDuration(l.resetsAt - root.now), fmtClock(l.resetsAt));
    }

    function statusText() {
        if (!result)
            return busy ? i18n("Loading…") : "";
        if (result.ok)
            return i18n("Updated %1", Qt.formatTime(new Date(result.fetchedAt), "HH:mm:ss"));
        let s = result.error === "token_expired"
            ? i18n("Token expired at %1, run claude to refresh it", fmtClock(result.tokenExpiresAt))
            : result.message;
        if (result.fetchedAt)
            s += "\n" + i18n("Showing data from %1", fmtClock(result.fetchedAt));
        return s;
    }

    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    Plasmoid.icon: "office-chart-ring-symbolic"

    toolTipMainText: i18n("Claude usage")
    toolTipSubText: {
        const lines = [];
        if (usage) {
            for (const l of usage.limits) {
                let line = l.label + ": " + Math.round(effectivePercent(l)) + "%";
                if (l.resetsAt && l.resetsAt > root.now)
                    line += " · " + i18n("resets in %1", fmtDuration(l.resetsAt - root.now));
                lines.push(line);
            }
        }
        if (stale)
            lines.push(statusText());
        return lines.join("\n");
    }

    compactRepresentation: CompactView {}
    fullRepresentation: FullView {}

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh now")
            icon.name: "view-refresh"
            onTriggered: root.refresh()
        },
        PlasmaCore.Action {
            text: i18n("Open claude.ai usage page")
            icon.name: "internet-web-browser"
            onTriggered: Qt.openUrlExternally("https://claude.ai/settings/usage")
        }
    ]

    onExpandedChanged: {
        if (expanded && (!result || !result.ok || Date.now() - result.fetchedAt > 20000))
            refresh();
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            root.busy = false;
            let r;
            try {
                r = JSON.parse(data["stdout"]);
            } catch (e) {
                r = { ok: false, error: "script", message: (data["stderr"] || String(e)).trim() };
            }
            if (!r.usage && root.result && root.result.usage) {
                r.usage = root.result.usage;
                r.fetchedAt = root.result.fetchedAt;
            }
            root.backoff = r.error === "rate_limited" ? Math.min(root.backoff * 2, 16) : 1;
            root.skipTicks = root.backoff - 1;
            root.now = Date.now();
            root.result = r;
        }
    }

    Timer {
        interval: Math.max(15, Plasmoid.configuration.refreshInterval) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (root.skipTicks > 0) {
                root.skipTicks--;
                return;
            }
            root.refresh();
        }
    }

    // Keeps "resets in …" countdowns and passed resets current between fetches.
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.now = Date.now()
    }
}
