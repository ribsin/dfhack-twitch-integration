# Changelog

## v1.0-alpha (in progress)

### Added
- Repository skeleton (`info.txt`, `LICENSE` MIT, `README.md`, `SPEC.md`, `.gitignore`).
- `scripts_modinstalled/` clean-room rewrite of all viewer-interaction scripts under the `dfxt-` prefix:
  - `dfxt-claim.lua`     — `!join` (FCFS / migrant / enemy)
  - `dfxt-status.lua`    — `!me`, `!available`
  - `dfxt-check.lua`     — `!check`, `!skills(full)`, `!health(full)`, `!kills(full)`, `!relatives`, `!prefs(full)`
  - `dfxt-religion.lua`  — `!worship`, `!unworship`, `!religions`, `!joinreligion`, `!leavereligion`
  - `dfxt-leave.lua`     — `!leave [days]`
  - `dfxt-squad.lua`     — `!squad`, `!unsquad`
  - `dfxt-mods.lua`      — `!mods` (450-char cap)
  - `dfxt-ping.lua`      — `!ping`
  - `dfxt-help.lua`      — `!commands`
  - `dfxt-petitions.lua` — petition queue + 90s polls, blocked by siege/FB
  - `dfxt-events.lua`    — event scheduler + bucket A/B/C voting
  - `dfxt-overlay.lua`   — DF-side chat-log overlay
  - `dfxt-common.lua`    — shared utilities (persist-table, role gate, name lookup, JSON config loader, chat sink)
- `_onload.lua` startup hint that detects the future plugin and prints the right setup message.
- `dfhack-config/DFxTwitch/config.example.json` template with full settings.
- `dev/` reserved for the native plugin source.

### Notes
- This is a clean-room implementation. No code is taken from any third-party Twitch-integration mod.
- Chat-log polling uses the same file the existing external bot writes to (`dfhack-config/DFxTwitch/chatlog.txt`), so anyone running an external bot today gets a soft-upgrade path.
- All scripts no-op gracefully on bad input. None throw `qerror` from chat-driven paths.
