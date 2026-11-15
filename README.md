# DFHack Twitch Integration (`dfxtwitch`)

A Dwarf Fortress mod that connects Twitch chat to fortress interaction.
Viewers can claim dwarves and use chat commands; petitions and events can use
native Twitch polls.

## Project Scope

DFHack Twitch Integration is a plugin package that connects Twitch chat to
fortress interaction in Dwarf Fortress.

## Functionality

- Receives Twitch chat messages and routes supported commands to DFHack Lua
  handlers.
- Supports viewer claim/status actions and fortress interaction commands.
- Supports religion, squad, leave, and utility command groups.
- Provides OAuth/auth helpers, diagnostics, and runtime debug utilities.
- Uses Twitch Helix for native polls and secure WebSockets for Twitch IRC chat.

## Architecture

The `scripts_modinstalled/dfxt-*.lua` scripts handle game-side actions. The
native DFHack plugin (`dfxtwitch.plug.dll`, source under `dev/`) handles
networking and authentication:

- HTTPS to Twitch Helix (WinHTTP) for `polls.create`, `polls.get`, and
  `polls.end`
- Twitch IRC over secure WebSockets (WSS) for chat read and write
- OAuth Authorization Code flow with a `http://localhost:3000` listener

The plugin pushes chat lines to Lua via `tw.set_message_handler`; Lua asks the
plugin to open Twitch polls via `tw.poll_create`.

```
Twitch chat --IRC--> plugin --push--> dfxt-router --> dfxt-* scripts
                       ^                                  |
                       |                                  v
                       +-- tw.send_chat <-- C.say() <-----+
                       +-- tw.poll_create / poll_get
Twitch native poll <-- Helix -- plugin
```

## Package Contents

- `hack/plugins/dfxtwitch.plug.dll`
- `hack/scripts/*.lua`
- `dfhack-config/DFxTwitch/config.example.json`
- Lua script sources in `scripts_modinstalled/`

## Compatibility

- Build target: Dwarf Fortress 53.17 with DFHack 53.17-r1. A clean Windows
  x64 Release build has been verified.
- Runtime compatibility is not yet tested; compilation alone does not verify
  plugin loading or gameplay behavior.
- The GitHub build/release workflow remains pinned to DFHack 53.12-r1, so its
  artifacts are not built for the current 53.17 target.
- Windows 10/11; the plugin uses WinHTTP WebSockets, and older Windows
  versions have not been validated.

## Requirements

- Twitch Affiliate or Partner status. Twitch's API does not allow
  non-Affiliate channels to create polls (`403 NOT_AFFILIATE`).
- A Twitch Developer App at <https://dev.twitch.tv/console/apps> with
  `http://localhost:3000` configured as an OAuth redirect URL. Save the
  resulting Client ID and Client Secret.
- The plugin DLL. Build from `dev/` (see `dev/README.md`) or use a matching
  artifact from this repository's GitHub Releases.

Chat uses WinHTTP WebSockets over TLS. OAuth credentials are protected with
Windows DPAPI for the current Windows user. These paths still require a live
connection test and have not been runtime-validated.

## Install

1. Subscribe to the mod on the Steam Workshop or place this folder in
   `<DF>/data/installed_mods/`.
2. Place `dfxtwitch.plug.dll` in `<DF>/hack/plugins/`.
3. Copy `config.example.json` to
   `<DF>/dfhack-config/DFxTwitch/config.json` and fill in `client_id` and
   `client_secret`.
4. In the DFHack console, run `dfxt-auth`. Authorize the app in the browser;
   the plugin captures the redirect, exchanges the code for tokens, and stores
   them in DPAPI-protected form in `config.json`.
5. Optionally run `dfxt-doctor` for a diagnostic check.
6. Activate the mod in your save's mod list and embark.

## Viewer Commands

See `SPEC.md` for the canonical list. A few highlights:

| Command | Tier | What it does |
|---|---|---|
| `!join` | any | Claim an unclaimed citizen (or migrant/enemy variants) |
| `!me` | any | Show the status of your dwarf |
| `!check <name>` | any | Look up someone else's dwarf |
| `!skills`, `!health`, `!kills`, `!relatives`, `!prefs` | any | Detail readouts |
| `!squad`, `!unsquad` | sub | Join or leave the active squad |
| `!worship`, `!leavereligion` | any | Religious life |
| `!leave [days]` | sub | Take leave from the fort |
| `!commands` | any | Show the main viewer commands |

Petitions use on-stream Twitch polls. The streamer must still accept approved
petitions in the game; denied petitions currently need a manual Reject click.
Migrant and enemy claims are queued, but the scripts do not yet rename
arriving units. Religion commands record the viewer's choice in mod data but
do not change the dwarf's in-game religion. Event polls announce the result
but do not yet apply the event's gameplay effect.

## Streamer-Side Commands

| Command | What it does |
|---|---|
| `dfxt-auth` | Authorize Twitch or renew authorization |
| `dfxt-doctor` | One-shot diagnostic |
| `dfxt-events fire <name>` | Force-fire an event |
| `dfxt-events bucket-c on/off` | Toggle the dangerous bucket |
| `enable dfxtwitch` | Enable or disable the plugin (auto-on at save load) |

## Why a Plugin Instead of an External Bot?

- One installation surface: subscribe, install the DLL, and run `dfxt-auth`.
- The plugin pushes chat events directly into Lua through
  `tw.set_message_handler`, without file-tail glue.
- Native Twitch polls use Twitch's poll widget rather than a custom chat tally.
- The localhost OAuth listener captures the redirect without manual token
  copy-paste.

## Development

The plugin source lives under `dev/`. See `dev/README.md` for the in-tree
DFHack build instructions and `.github/workflows/build.yml` for the CI build.

## License

MIT. See [LICENSE](LICENSE).
