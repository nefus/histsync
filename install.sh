#!/bin/bash
# Install or remove histsync.
#
#   ./install.sh [-p PEER]... [--no-systemd] [--uninstall] [SSH-DESTINATION]
#
# Without SSH-DESTINATION, histsync is installed locally for the current user;
# with SSH-DESTINATION (e.g. "user@server"), the package is copied there and
# installed on that host. -p registers peers the host syncs with (like
# "histsync add PEER"); this requires non-interactive SSH access from the
# host to the peer. Alternatively, another host registers the new one as its
# peer. Requirements: bash >= 4.4, python3 >= 3.7.
#
# Installed files:
#   ~/.local/bin/histsync                    sync, search, peer management
#   ~/.local/share/histsync/histsync.bash    hook, sourced from ~/.bashrc
#   ~/.local/share/histsync/history.sqlite   local database (kept on uninstall)
#   ~/.config/histsync/config                configuration (kept on uninstall)
#   ~/.config/systemd/user/histsync.{service,timer}
# Without a systemd user instance, the hook triggers sync itself.

set -euo pipefail

src=$(cd "$(dirname "$0")" && pwd)
peers=() systemd=auto uninstall= target=
while (( $# )); do
    case $1 in
        -p|--peer) peers+=("$2"); shift ;;
        --no-systemd) systemd=no ;;
        --uninstall) uninstall=1 ;;
        -h|--help) sed -n '2,/^$/s/^# \{0,1\}//p' "$0"; exit 0 ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *) target=$1 ;;
    esac
    shift
done

if [[ -n $target ]]; then
    args=()
    for p in "${peers[@]}"; do args+=(-p "$p"); done
    [[ $systemd == no ]] && args+=(--no-systemd)
    [[ -n $uninstall ]] && args+=(--uninstall)
    script='set -e; d=$(mktemp -d); trap "rm -rf \"$d\"" EXIT; tar -C "$d" -xf -; bash "$d/install.sh" "$@"'
    tar -C "$src" -cf - histsync histsync.bash histsync.service histsync.timer install.sh |
        ssh "$target" "bash -c $(printf %q "$script") install.sh ${args[*]@Q}"
    exit
fi

bin=$HOME/.local/bin
share=$HOME/.local/share/histsync
conf_dir=${XDG_CONFIG_HOME:-$HOME/.config}/histsync
conf=$conf_dir/config
units=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
bashrc=$HOME/.bashrc
hook_line='[ -r ~/.local/share/histsync/histsync.bash ] && . ~/.local/share/histsync/histsync.bash  # histsync'

have_systemd ()
{
    [[ $systemd != no ]] && systemctl --user show-environment >/dev/null 2>&1
}

set_conf ()
{
    if grep -q "^$1=" "$conf" 2>/dev/null; then
        sed -i "s|^$1=.*|$1=$2|" "$conf"
    else
        echo "$1=$2" >> "$conf"
    fi
}

if [[ -n $uninstall ]]; then
    if have_systemd; then
        systemctl --user disable --now histsync.timer 2>/dev/null || true
    fi
    rm -f "$units/histsync.service" "$units/histsync.timer" "$bin/histsync" "$share/histsync.bash"
    have_systemd && systemctl --user daemon-reload
    [[ -f $bashrc ]] && sed -i '/# histsync$/d' "$bashrc"
    echo "histsync removed. Database, spool and configuration are kept in"
    echo "  $share, ${XDG_STATE_HOME:-$HOME/.local/state}/histsync and $conf_dir"
    exit 0
fi

python3 -c 'import sys; sys.exit(sys.version_info < (3, 7))' ||
    { echo "python3 >= 3.7 is required" >&2; exit 1; }

install -d "$bin" "$share" "$conf_dir"
install -m 755 "$src/histsync" "$bin/histsync"
install -m 644 "$src/histsync.bash" "$share/histsync.bash"

if [[ ! -f $conf ]]; then
    cat > "$conf" <<'EOF'
# histsync configuration (KEY=VALUE, also sourced by bash)
# Peers are managed with "histsync add/remove HOST", not in this file.
# additional ssh options, e.g. HISTSYNC_SSH_OPTS="-p 2222"
#HISTSYNC_SSH_OPTS=
# local database
#HISTSYNC_DB=~/.local/share/histsync/history.sqlite
EOF
fi

if have_systemd; then
    install -d "$units"
    install -m 644 "$src/histsync.service" "$src/histsync.timer" "$units/"
    systemctl --user daemon-reload
    systemctl --user enable --now histsync.timer
    set_conf HISTSYNC_SHELL_SYNC 0
    mode="systemd timer (every 2 minutes)"
else
    set_conf HISTSYNC_SHELL_SYNC 1
    mode="hook in the background (at most every 5 minutes)"
fi

if ! grep -qF "$hook_line" "$bashrc" 2>/dev/null; then
    sed -i '/# histsync$/d' "$bashrc" 2>/dev/null || true
    # Append at the end, so the hook is added after all PROMPT_COMMAND assignments.
    printf '\n%s\n' "$hook_line" >> "$bashrc"
fi

echo "histsync installed on $(hostname); sync via $mode."
for p in "${peers[@]}"; do
    "$bin/histsync" add "$p" ||
        echo "Note: $p is not reachable right now, the next sync will retry." >&2
done
"$bin/histsync" sync -q || true
"$bin/histsync" status
echo "New shells record the history; in open shells run: . ~/.bashrc"
