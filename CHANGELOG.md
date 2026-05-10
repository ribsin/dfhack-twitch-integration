# Changelog

## v1.0 (in progress) — plugin architecture, pinned to DFHack 53.12-r1

### Pinned target
- **Dwarf Fortress 53.12** + **DFHack 53.12-r1**.
- `.github/workflows/build.yml` `DFHACK_TAG=53.12-r1` — CI builds the plugin against this exact source tree.
- `info.txt` updated to `DISPLAYED_VERSION:1.0` and the description now states the DF/DFHack version requirement and the GitHub-Releases location of the matching DLL.
- `dev/README.md` shows the explicit `git clone --branch 53.12-r1 …` step.

### Added
- **Native DFHack plugin** (`dev/`): `dfxtwitch.plug.dll/.so` source.
  Replaces the old "external bot + chat-log file tail" path entirely.
  - `irc_client.cpp` — raw-TCP Twitch IRC client (auto-PONG, exponential reconnect, IRCv3 tags, role-from-badges)
  - `helix_client.cpp` — libcurl wrapper around `id.twitch.tv/oauth2/validate` and `api.twitch.tv/helix/polls` (create / get / end)
  - `oauth_server.cpp` — Authorization-Code flow with a `http://localhost:3000` listener, browser-launched
  - `token_store.cpp` — reads / writes `dfhack-config/DFxTwitch/config.json` (token fields only; preserves user-edited keys)
  - `event_queue.cpp` — thread-safe MPSC queue draining on the DFHack main-thread tick
  - `lua_api.cpp` — exposes `require('plugins.dfxtwitch')` with `connect`, `send_chat`, `auth_login`, `validate_token`, `poll_create / poll_get / poll_cancel`, `set_message_handler`, `set_poll_handler`, `status`
- **`dfxt-router.lua`** — chat-line dispatcher. Registers with `tw.set_message_handler`; performs role gate, per-user cooldown, and arg-shaping for every viewer command.
- **`dfxt-poll.lua`** — wraps `tw.poll_create` and the 5 s `tw.poll_get` polling loop. Single source of truth for "open a Twitch native poll, await a winner, fire callback".
- **`dfxt-auth.lua`** — one-shot OAuth runner; opens the browser, captures the code, persists tokens.
- **`dfxt-doctor.lua`** — health check (plugin loaded, config present, token valid, scopes correct, IRC connected).
- **`.github/workflows/build.yml`** — cross-builds the plugin on Windows + Linux against a pinned DFHack tag and attaches artifacts to draft Releases.

### Changed
- `dfxt-petitions.lua` and `dfxt-events.lua`: poll lifecycle delegated to `dfxt-poll`. They now request a poll, get a callback with the winner, and act on it — no more "POLL_OPEN" announcement that the external bot had to interpret.
- `dfxt-overlay.lua`: dropped `chatlog.txt` file-tail logic. The chat overlay buffer is filled by `dfxt-router` directly. Heartbeat still drives `dfxt-poll.tick`, `dfxt-leave`, `dfxt-petitions`, and `dfxt-events`.
- `dfxt-common.say()`: primary path is now `tw.send_chat` (IRC). The `chat-out.txt` append is kept as a fallback for streams running without the plugin.
- `_onload.lua`: connects IRC, starts the router, and validates the token at save load.
- `config.example.json`: replaced bot-era `bot_username` / `oauth_token`-as-chat-token with the Helix-era `client_id` / `client_secret` / `oauth_token` / `refresh_token` / `channel_id` set; documents required scopes and the `http://localhost:3000` redirect URI.

### Removed
- The "external Twitch bot reads chatlog.txt and writes to chat-out.txt" indirection. The plugin handles both directions in-process.

### Notes
- Affiliate or Partner status is required for Twitch native polls. The mod will not attempt poll creation if `channel_id` is blank or Helix returns 403; petitions will fall back to popup-only resolution.
- The plugin is a single self-contained DLL/SO with statically linked libcurl. No additional runtime dependencies.

---

## v1.0-alpha — initial skeleton

### Added
- Repository skeleton (`info.txt`, `LICENSE` MIT, `README.md`, `SPEC.md`, `.gitignore`).
- `scripts_modinstalled/` clean-room rewrite of all viewer-interaction scripts under the `dfxt-` prefix.
- `_onload.lua` startup hint.
- `dfhack-config/DFxTwitch/config.example.json` template.
- `dev/` reserved for the native plugin source.

### Notes
- Clean-room implementation; no code taken from any third-party Twitch-integration mod.
- All scripts no-op gracefully on bad input — none throw `qerror` from chat-driven paths.
