#!/usr/bin/env bash
# Install, upgrade or remove the Claude Usage plasmoid for the current user.
#
#   ./install.sh                 install or upgrade, add to the system tray, restart plasmashell
#   ./install.sh --no-tray       don't add it to the system tray
#   ./install.sh --no-restart    don't restart plasmashell (changes apply on next login)
#   ./install.sh --uninstall     remove the plasmoid and its tray entry
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

add_tray=1
restart=1
uninstall=0
for arg in "$@"; do
    case "$arg" in
        --no-tray) add_tray=0 ;;
        --no-restart) restart=0 ;;
        --uninstall) uninstall=1 ;;
        -h|--help) sed -n '2,8s/^# \{0,1\}//p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg (see --help)" >&2; exit 1 ;;
    esac
done

die() { echo "Error: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

have kpackagetool6 || die "kpackagetool6 not found. This widget needs KDE Plasma 6."
have python3 || die "python3 not found. The widget uses it to fetch usage data."

# Plugin id comes from metadata.json, so a renamed fork needs no changes here.
plugin_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["KPlugin"]["Id"])' package/metadata.json)

plasma_running() { have dbus-send && dbus-send --session --print-reply --dest=org.freedesktop.DBus \
    /org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner string:org.kde.plasmashell 2>/dev/null | grep -q 'boolean true'; }

# Runs a Plasma desktop script inside the running plasmashell.
plasma_script() {
    dbus-send --session --print-reply --dest=org.kde.plasmashell /PlasmaShell \
        org.kde.PlasmaShell.evaluateScript "string:$1" >/dev/null
}

# Adds the plugin to (op=add) or removes it from (op=remove) every system tray's entry lists.
tray_entry() {
    plasma_script "
const id = '$plugin_id', op = '$1';
for (const p of panels()) for (const w of p.widgets('org.kde.plasma.systemtray')) {
    w.currentConfigGroup = ['General'];
    for (const key of ['extraItems', 'knownItems']) {
        let list = JSON.parse(JSON.stringify(w.readConfig(key, [])));
        const has = list.indexOf(id) >= 0;
        if (op === 'add' && !has) list.push(id);
        else if (op === 'remove' && has) list = list.filter(x => x !== id);
        else continue;
        w.writeConfig(key, list);
    }
    w.reloadConfig();
}"
}

restart_plasma() {
    echo "Restarting plasmashell..."
    if have systemctl && systemctl --user is-active --quiet plasma-plasmashell.service; then
        systemctl --user restart plasma-plasmashell.service
    else
        if have kquitapp6; then kquitapp6 plasmashell >/dev/null 2>&1 || true; fi
        if have kstart; then
            kstart plasmashell >/dev/null 2>&1
        else
            setsid plasmashell --replace >/dev/null 2>&1 < /dev/null &
        fi
    fi
}

if (( uninstall )); then
    if plasma_running && ! tray_entry remove; then
        echo "Warning: could not remove the system tray entry." >&2
    fi
    kpackagetool6 -t Plasma/Applet --remove "$plugin_id"
    rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/claude-usage-plasmoid"
    (( restart )) && plasma_running && restart_plasma
    echo "Removed $plugin_id."
    exit 0
fi

credentials="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
if [[ ! -r "$credentials" ]]; then
    echo "Warning: $credentials not found. Log in with Claude Code (run 'claude') first," >&2
    echo "         or set the credentials path in the widget settings." >&2
fi

if kpackagetool6 -t Plasma/Applet --show "$plugin_id" >/dev/null 2>&1; then
    kpackagetool6 -t Plasma/Applet --upgrade package
else
    kpackagetool6 -t Plasma/Applet --install package
fi

tray_hint="Add it via System Tray settings -> Entries -> Claude Usage, or put it on a panel."
if (( add_tray )); then
    if ! plasma_running; then
        echo "plasmashell is not running, skipping tray setup. $tray_hint"
    elif tray_entry add; then
        echo "Added to the system tray."
    else
        echo "Could not add it to the system tray automatically. $tray_hint"
    fi
fi

# The tray loads new widgets and plasmashell reloads changed QML only on start.
if (( restart )) && plasma_running; then
    restart_plasma
else
    echo "Restart plasmashell or log out and back in to load the widget."
fi
echo "Done."
