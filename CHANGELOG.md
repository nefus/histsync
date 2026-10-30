# Changelog

All notable changes to histsync are documented in this file. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project uses [Semantic Versioning](https://semver.org/). Until 1.0.0,
options and behaviour may still change between minor versions.

## [Unreleased]

## [0.1.0] - 2026-10-30

First public release.

### Added

- Bash hook (`histsync.bash`) that records every command with host, user,
  start time, time zone, start directory, exit status, TTY,
  `$SSH_CONNECTION` and shell PID to a local spool; works alongside
  starship and VTE and honours `HISTCONTROL`/`HISTIGNORE`.
- Peer-to-peer sync over SSH (`histsync sync`, `add`, `remove`, `peers`):
  every host keeps the full history of all hosts in a local SQLite
  database, exchanges new entries in both directions over one connection
  and converges transitively. Peers only need `python3`; the code is sent
  along.
- `histsync delete` with tombstones that propagate to all peers.
- `histsync search` with filters for host, directory, time, origin and
  exact command; without filters it shows the current host and directory.
  `histsync` without a subcommand runs `search`.
- `histsync import-bash-history` and `install.sh --import-bash-history`
  to import an existing `~/.bash_history` (commands with timestamps).
- Spool format documented as the generic way to import other data.
- Tab completion for `histsync` and its aliases, with hosts, directories,
  origins and peers from the local database.
- `install.sh` for local and remote (SSH) installation with a systemd user
  timer, or a hook-triggered sync without systemd.
- `histsync --version`; `histsync status` shows the version.

[Unreleased]: https://github.com/nefus/histsync/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/nefus/histsync/releases/tag/v0.1.0
