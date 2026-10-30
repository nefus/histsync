# histsync

Peer-to-peer sync of Bash history between hosts: every host keeps the
complete history of all hosts in a local SQLite database and reconciles it
with its peers over SSH. The regular Bash history (`HISTFILE`) is left
untouched.

- `histsync.bash` (a `PROMPT_COMMAND` hook) appends every command as a JSON
  line to `~/.local/state/histsync/spool.jsonl`: host, user, start time, time
  zone, start directory, command, exit status, TTY, `$SSH_CONNECTION` and
  shell PID. Commands starting with a space or excluded by `HISTIGNORE` are
  skipped, just like in the regular history. The hook works alongside
  starship and VTE.
- `histsync sync` (a systemd user timer every 2 minutes; without systemd the
  hook triggers it every 5 minutes) moves the spool into
  `~/.local/share/histsync/history.sqlite` and then exchanges new entries
  with each peer in both directions over a single SSH connection. If a peer
  is unreachable, the next run catches up.
- Entries are immutable and have unique IDs, so the databases converge, also
  transitively (A-B and B-C is enough for A to get C's entries).
- Only the host running `sync` needs SSH access. The peer only needs
  `python3`: the source is sent along, so histsync does not have to be
  installed there (in that case only its database is synced, not its own
  commands).
- `histsync delete` removes entries and records tombstones that travel to all
  peers like the entries do; entries with a tombstone are never inserted
  again. Rows deleted directly via SQL come back from the next peer.
- Directories and the database are readable by the user only (700/600), since
  command lines may contain passwords.

Requirements: bash >= 4.4, python3 >= 3.7 (standard library only), ssh.

## Installation and peers

    ./install.sh                         # install locally
    ./install.sh user@server             # install on another host via SSH
    ./install.sh -p laptop user@server   # ... and register laptop as its peer
    histsync add laptop                  # register a peer and sync right away
    histsync remove laptop               # unregister a peer (its entries stay)
    histsync peers

`install.sh` appends one line to `~/.bashrc`, installs the timer and service
as systemd user units (if available) and creates `~/.config/histsync/config`.
To remove: `./install.sh --uninstall [HOST]` (database and configuration are
kept).

## Usage

    histsync search                       # history of this host in the current directory
    histsync search -a                    # all hosts and directories
    histsync search -. git                # this host and directory, commands containing "git"
    histsync status                       # database per host, spool, peers with last sync
    histsync sync [--peer HOST]           # sync now
    histsync search docker compose        # commands containing both words
    histsync search -H 'web%' -d '%/src/%' -s 2026-01-01 -n 100 make
    histsync delete -x 'mysql -psecret'   # exactly this command, on all hosts
    histsync delete -H laptop -s 2026-10-30 passwd   # shows matches, asks first
    sqlite3 ~/.local/share/histsync/history.sqlite \
        "select * from history_v where exit <> 0 order by time desc limit 20"

Without any filter, `histsync search` means `--here` (current host and
directory, shown without the host and directory columns). A handy alias:

    alias hs='histsync search'

Tab completion for `histsync` is part of `histsync.bash` and does not need
the bash-completion package. It completes subcommands and options, hosts
(`-H`), directories (`-d`), origins (`-o`) and peers from the local database,
and SSH hosts for `histsync add`. Aliases of `histsync` (like `hs` above) get
the completion automatically if they are defined before `histsync.bash` is
sourced (as with `~/.bash_aliases`); otherwise add
`complete -F _histsync_complete ALIAS`.

## Configuration

`~/.config/histsync/config` (KEY=VALUE; environment variables take precedence):

| Variable              | Meaning                                                 |
|-----------------------|---------------------------------------------------------|
| `HISTSYNC_DB`         | local database (default `~/.local/share/histsync/history.sqlite`) |
| `HISTSYNC_SSH_OPTS`   | additional ssh options, e.g. `-p 2222`                  |
| `HISTSYNC_SHELL_SYNC` | `1` = the hook triggers `sync` itself (without systemd) |
| `HISTSYNC_HOSTNAME`   | own name towards peers (default: short hostname)        |

## Spool format and imports

Each line in the spool is a JSON object; `sync` (and `search`) move it into
the database. This also works for importing old data: generate lines, append
them to `~/.local/state/histsync/spool.jsonl` and run `histsync sync`.

| Field     | Required | Content                                             |
|-----------|----------|-----------------------------------------------------|
| `id`      | yes      | globally unique and stable; a known ID is ignored   |
| `host`    | yes      | host the command ran on                             |
| `ts`      | yes      | start time, Unix seconds                            |
| `cmd`     | yes      | command                                             |
| `user`, `tz`, `pwd`, `exit`, `tty`, `ssh`, `session` | no | as written by the hook |
| `origin`  | no       | source, `hook` or e.g. `import:source`              |

Use a deterministic ID for imports (e.g. `import:file:line`) so that
repeating an import is harmless. To undo an import:
`histsync delete -o 'import:file'`.

## License

MIT, see [LICENSE](LICENSE).
