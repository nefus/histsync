# histsync: append every command with host, directory, timestamp and exit
# status to the local spool; "histsync sync" reconciles it with the peers.
# Sourced from ~/.bashrc (see install.sh). The regular Bash history
# (HISTFILE, HISTCONTROL, ...) is left untouched.

[[ $- == *i* ]] || return 0
[[ -n ${_histsync_loaded:-} ]] && return 0
_histsync_loaded=1

_histsync_dir="${XDG_STATE_HOME:-$HOME/.local/state}/histsync"
_histsync_config="${XDG_CONFIG_HOME:-$HOME/.config}/histsync/config"
mkdir -p -m 700 "$_histsync_dir" 2>/dev/null
[[ -r $_histsync_config ]] && . "$_histsync_config"
_histsync_last=
_histsync_started=
_histsync_synced=$SECONDS
_histsync_pwd=$PWD
_histsync_tty=$(tty 2>/dev/null) || _histsync_tty=

# _histsync_json VAR VALUE: VALUE as JSON string in VAR (without a subshell)
_histsync_json ()
{
    local s=$2
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\t'/\\t}
    s=${s//$'\r'/\\r}
    s=${s//[$'\001'-$'\037']/?}
    printf -v "$1" '"%s"' "$s"
}

_histsync_hook ()
{
    # Save the exit status first; if starship ran before, it already has it.
    local rc=$?
    [[ -n ${STARSHIP_CMD_STATUS:-} && ${PROMPT_COMMAND[0]} == starship_precmd ]] && rc=$STARSHIP_CMD_STATUS
    local entry ts cmd
    entry=$(HISTTIMEFORMAT='%s ' builtin history 1)
    # "  123* 1730284000 command" - number and timestamp identify the entry
    if [[ $entry =~ ^\ *([0-9]+)\*?\ +([0-9]+)\ (.*)$ ]]; then
        ts=${BASH_REMATCH[2]}
        cmd=${BASH_REMATCH[3]}
        entry="${BASH_REMATCH[1]} $ts"
        # First prompt: the entry comes from the loaded history file.
        # Unchanged: the command did not go into the history (leading space, HISTIGNORE, ...).
        if [[ -n $_histsync_started && $entry != "$_histsync_last" ]]; then
            local tz j_id j_host j_user j_pwd j_cmd j_tty j_ssh
            printf -v tz '%(%z)T' "$ts"
            _histsync_json j_id "$HOSTNAME:$$:${EPOCHREALTIME:-$ts.$RANDOM}"
            _histsync_json j_host "$HOSTNAME"
            _histsync_json j_user "${USER:-$LOGNAME}"
            # Start directory: PWD at the previous prompt (not after a cd)
            _histsync_json j_pwd "$_histsync_pwd"
            _histsync_json j_cmd "$cmd"
            _histsync_json j_tty "$_histsync_tty"
            _histsync_json j_ssh "${SSH_CONNECTION:-}"
            printf '{"id":%s,"host":%s,"user":%s,"ts":%d,"tz":"%s","pwd":%s,"cmd":%s,"exit":%d,"tty":%s,"ssh":%s,"session":"%d","origin":"hook"}\n' \
                "$j_id" "$j_host" "$j_user" "$ts" "$tz" "$j_pwd" "$j_cmd" "$rc" "$j_tty" "$j_ssh" "$$" \
                >> "$_histsync_dir/spool.jsonl"
        fi
        _histsync_last=$entry
    fi
    _histsync_started=1
    _histsync_pwd=$PWD
    # Without a systemd timer: sync in the background at most every 5 minutes.
    if [[ ${HISTSYNC_SHELL_SYNC:-0} == 1 ]] && (( SECONDS - _histsync_synced >= 300 )); then
        _histsync_synced=$SECONDS
        local bin=$HOME/.local/bin/histsync
        [[ -x $bin ]] || bin=histsync
        ("$bin" sync -q >/dev/null 2>&1 &)
    fi
    return $rc
}

# Prepend, so that $? is still the status of the command. A starship loaded
# later moves the hook into STARSHIP_PROMPT_COMMAND and provides the status
# in STARSHIP_CMD_STATUS.
if [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" == "declare -a"* ]]; then
    PROMPT_COMMAND=(_histsync_hook "${PROMPT_COMMAND[@]}")
else
    PROMPT_COMMAND="_histsync_hook${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
fi
