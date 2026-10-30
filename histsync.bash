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

# Completion for histsync and aliases of it (e.g. alias hs='histsync search');
# values for -H, -d, -o and peers come from the local database. Works without
# the bash-completion package.
_histsync_complete ()
{
    local -a words=("${COMP_WORDS[@]}") expansion
    local cword=$COMP_CWORD
    # Alias: complete as if it were expanded
    if [[ -n ${BASH_ALIASES[${words[0]}]-} ]]; then
        read -ra expansion <<< "${BASH_ALIASES[${words[0]}]}"
        words=("${expansion[@]}" "${words[@]:1}")
        (( cword += ${#expansion[@]} - 1 ))
    fi
    local cur=${words[cword]} prev=${words[cword-1]}
    local bin=$HOME/.local/bin/histsync sub=${words[1]} opts
    [[ -x $bin ]] || bin=histsync
    COMPREPLY=()
    if (( cword == 1 )) && [[ $cur != -* ]]; then
        COMPREPLY=($(compgen -W "sync add remove peers status search delete import-bash-history" -- "$cur"))
        return
    fi
    # Without a subcommand, histsync runs search
    [[ $sub == -* ]] && sub=search
    case $prev in
        -H|--host|-o|--origin|--peer)
            local what=hosts
            [[ $prev == -o || $prev == --origin ]] && what=origins
            [[ $prev == --peer ]] && what=peers
            COMPREPLY=($(compgen -W "$("$bin" _complete $what 2>/dev/null)" -- "$cur"))
            # "import:..." contains a colon, which is a word break in Bash
            declare -F __ltrim_colon_completions >/dev/null && __ltrim_colon_completions "$cur"
            return ;;
        -d|--dir)
            local IFS=$'\n' dir
            for dir in $("$bin" _complete dirs "$cur" 2>/dev/null); do
                COMPREPLY+=("$(printf '%q' "$dir")")
            done
            return ;;
        -s|--since|-n|--limit|-x|--exact|--id)
            return ;;
    esac
    case $sub in
        search) opts="-H --host -d --dir -s --since -x --exact -o --origin -. --here -a --all -n --limit" ;;
        delete) opts="-H --host -d --dir -s --since -x --exact -o --origin --id -y --yes" ;;
        sync)   opts="-q --quiet --peer" ;;
        import-bash-history)
                opts="--until --dry-run"
                if [[ $cur != -* && $prev != --until ]]; then
                    compopt -o default 2>/dev/null
                    return
                fi ;;
        add)    opts="--no-sync"
                if [[ $cur != -* ]]; then
                    if declare -F _known_hosts_real >/dev/null; then
                        _known_hosts_real -- "$cur"
                    else
                        COMPREPLY=($(compgen -W "$(awk 'tolower($1) == "host" { for (i = 2; i <= NF; i++)
                            if ($i !~ /[*?]/) print $i }' ~/.ssh/config 2>/dev/null)" -- "$cur"))
                    fi
                    return
                fi ;;
        remove) if [[ $cur != -* ]]; then
                    COMPREPLY=($(compgen -W "$("$bin" _complete peers 2>/dev/null)" -- "$cur"))
                    return
                fi ;;
    esac
    [[ $cur == -* ]] && COMPREPLY=($(compgen -W "$opts -h --help" -- "$cur"))
}
complete -F _histsync_complete histsync
# Aliases defined before this file is sourced get the completion too; for
# later ones: complete -F _histsync_complete ALIAS
_histsync_alias=
for _histsync_alias in "${!BASH_ALIASES[@]}"; do
    [[ ${BASH_ALIASES[$_histsync_alias]%% *} == *histsync ]] && complete -F _histsync_complete "$_histsync_alias"
done
unset _histsync_alias

# Prepend, so that $? is still the status of the command. A starship loaded
# later moves the hook into STARSHIP_PROMPT_COMMAND and provides the status
# in STARSHIP_CMD_STATUS.
if [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" == "declare -a"* ]]; then
    PROMPT_COMMAND=(_histsync_hook "${PROMPT_COMMAND[@]}")
else
    PROMPT_COMMAND="_histsync_hook${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
fi
