# DFHack Twitch Integration (`dfxtwitch`)

A Dwarf Fortress mod that turns your Twitch chat into the labour pool, jury,
and chaos engine of your fortress. Viewers `!join` to claim a dwarf, then
control them with chat commands. Petitions and surprise events are decided
on-stream by **native Twitch polls** — no external bot, no browser overlay,
just chat votes that show up in the real Twitch poll widget.

> **Status: v1.0-alpha.** Lua scripts are clean-room implementations and run.
> The `dfxtwitch.plug.dll` source is in `dev/` and builds via the included
> GitHub Actions workflow against a pinned DFHack version.

---

## Architecture in one paragraph

The `scripts_modinstalled/dfxt-*.lua` scripts handle every game-side action
(claim a dwarf, run a check, queue a petition, schedule an event). A native
DFHack plugin (`dfxtwitch.plug.dll`, source under `dev/`) handles everything
the bundled DFHack Lua can't:

- **HTTPS to Twitch Helix** (libcurl) for `polls.create / polls.get / polls.end`
- **Twitch IRC over TCP** for chat read & write
- **OAuth Authorization-Code flow** with a `http://localhost:3000` listener

The plugin pushes chat lines to Lua via `tw.set_message_handler`, and the
Lua side asks the plugin to open Twitch polls via `tw.poll_create`.

```
Twitch chat ──IRC──▶ plugin ─push─▶ dfxt-router ─run──▶ dfxt-* scripts
                       ▲                                       │
                       │                                       ▼
                       └─── tw.send_chat (replies) ◀── C.say()
                                                              │
                       ┌─────── tw.poll_create / poll_get ◀────┘
Twitch native poll ◀─Helix─ plugin
```

## Requirements

- **Dwarf Fortress (Steam) 51.x** + **DFHack 51.x** — same version on both.
- **Twitch Affiliate or Partner status.** Twitch's API will not let
  non-Affiliate channels create polls (`403 NOT_AFFILIATE`). This is a hard
  Twitch policy we can't work around.
- **A Twitch Developer App** at <https://dev.twitch.tv/console/apps>:
  - **OAuth Redirect URLs:** `http://localhost:3000`
  - Save the resulting **Client-ID** and **Client-Secret**.
- **The plugin DLL.** Either build from `dev/` (see `dev/README.md`) or grab
  the matching artifact from this repo's GitHub Releases.

## Install

1. Subscribe to the mod on the Steam Workshop **or** drop this folder into
   `<DF>/data/installed_mods/`.
2. Drop `dfxtwitch.plug.dll` (Windows) or `dfxtwitch.plug.so` (Linux) into
   `<DF>/hack/plugins/`.
3. Copy `config.example.json` to `<DF>/dfhack-config/DFxTwitch/config.json`
   and fill in `client_id` + `client_secret`.
4. In DFHack console: `dfxt-auth` — your browser opens, you click
   **Authorize** on Twitch, the plugin captures the redirect, exchanges the
   code for tokens, and writes them to `config.json` automatically.
5. (Optional) `dfxt-doctor` — prints a green-tick health check.
6. Activate the mod in your save's mod list and embark.

## Viewer commands

See `SPEC.md` for the canonical list. A few highlights:

| Command | Tier | What it does |
|---|---|---|
| `!join`           | any | Claim an unclaimed citizen (or migrant / enemy variants) |
| `!me`             | any | Whisper-style status of your dwarf |
| `!check <name>`   | any | Look up someone else's dwarf |
| `!skills`, `!health`, `!kills`, `!relatives`, `!prefs` | any | Detail readouts |
| `!squad`, `!unsquad` | sub | Join / leave the active squad |
| `!worship`, `!leavereligion` | any | Religious life |
| `!leave [days]`   | sub | Take leave from the fort |
| `!commands`       | any | List everything |

Petitions and `!event` outcomes are decided by **on-stream Twitch polls**
that the plugin opens via Helix. The streamer never has to click anything.

## Streamer-side commands

| Command | What it does |
|---|---|
| `dfxt-auth`         | OAuth dance against Twitch (one-time, occasionally to refresh) |
| `dfxt-doctor`       | One-shot diagnostic |
| `dfxt-events fire <name>` | Force-fire an event |
| `dfxt-events bucket-c on/off` | Toggle the dangerous bucket |
| `enable dfxtwitch`  | Plugin on/off (auto-on at save load) |

## Why a plugin instead of an external bot?

- **One installation surface.** Subscribe → drop one DLL → run `dfxt-auth`.
  No Python/Node bot to babysit.
- **No file-tail glue.** The plugin pushes chat events straight into Lua via
  `tw.set_message_handler` — gone is the `chatlog.txt` / `chat-out.txt`
  ping-pong that a bot needed.
- **Native Twitch polls.** Chat votes use Twitch's real poll widget —
  visible to every viewer, in their language, with their predictions UI —
  not a chat-tally we'd have to render ourselves.
- **OAuth that doesn't suck.** The localhost:3000 listener captures the
  redirect automatically. The streamer never copy-pastes a token.

## Development

The plugin source lives under `dev/`. See `dev/README.md` for the in-tree
DFHack build instructions and `.github/workflows/build.yml` for the CI build.

## License

MIT. See `LICENSE`.
