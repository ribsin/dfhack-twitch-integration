# Changelog

## v1.0-rc5 — CI: break cpanm MakeMaker self-upgrade circle

### Fixed
- **CI Perl step looped on a cpanm circular dependency.** With pinned
  Strawberry 5.38 in place, asking cpanm to install `ExtUtils::Manifest`
  triggered a MakeMaker upgrade; cpanm Configured the new
  `ExtUtils::MakeMaker-7.78`, then tried to install `Pod::Man` (`podlators`),
  whose `Makefile.PL` bails because the *new* MakeMaker isn't installed yet —
  cascading failure all the way back up:
  `Module 'ExtUtils::MakeMaker' is not installed`. Plugin source is unchanged.

### Changed
- `.github/workflows/build.yml`:
  - **Removed** the explicit `cpanm --notest ExtUtils::Manifest` step. It was
    a defensive carry-over from rc4, but Strawberry 5.38 already ships
    `ExtUtils::Manifest`, and the line was the trigger for the MakeMaker
    self-upgrade circle.
  - **Added** `cpanm --notest --installdeps ExtUtils::MakeMaker` *before* the
    XML modules. `--installdeps` installs MakeMaker's prereqs (`Pod::Man`,
    `File::Path`, …) without installing MakeMaker itself, so any later
    upgrade triggered by `Alien::Libxml2` / `XML::LibXML` can complete
    without cycling back through `podlators`.

## v1.0-rc4 — CI: pin Strawberry Perl 5.38

### Fixed
- **CI Perl step broken on the new windows-2022 image.** The Strawberry Perl
  5.42 that now ships with the runner image bundles a fatpacked `cpanm` that
  trips on modern `ExtUtils::MakeMaker`:
  `Attempt to call undefined import method ... via package "CPAN::Meta::Prereqs"`
  and lacks `ExtUtils::Manifest`, so `MakeMaker`'s Configure step also fails
  with `Can't locate ExtUtils/Manifest.pm in @INC`. Plugin source is unchanged.

### Changed
- `.github/workflows/build.yml`:
  - Added a `shogo82148/actions-setup-perl@v1` step pinning Strawberry Perl
    `5.38` (`distribution: strawberry`) **before** the cpanm step. Pinning
    insulates us from future Strawberry breakage in the same way the
    `windows-2022` runner pin insulates us from future MSVC breakage.
  - The cpanm step now installs `ExtUtils::Manifest` explicitly first, then
    `XML::LibXML` + `XML::LibXSLT`. Removes one whole class of "the world
    shifted under us" failures.

## v1.0-rc3 — CI: pin VS 2022 toolset

### Fixed
- **CI build broken by GitHub runner image bump.** `windows-latest` now ships
  Visual Studio 18 / MSVC toolset 14.50, which DFHack's top-level CMakeLists
  rejects at configure time:
  `MSVC 2022 version 1930 to 1944 is required, Version Found: 1950`.
  Plugin source is unchanged; this is purely a CI pin.

### Changed
- `.github/workflows/build.yml`:
  - `runs-on: windows-latest` → `runs-on: windows-2022` (DFHack requires MSVC
    toolset 14.30..14.44 / VS 2022).
  - Added `vsversion: 2022` to the `ilammy/msvc-dev-cmd@v1` step as a
    belt-and-braces guard against future side-by-side VS 18 installs.
  - Hardened the Perl XML modules step: dropped `|| true`, added
    `set -o pipefail`, and bumped `tail -n 30` → `tail -n 200`. A silent
    `cpanm` failure here would have been the next confusing build break, since
    DFHack's codegen needs `XML::LibXML` to chew `library/xml`.

## v1.0-rc2 — Windows-only, WinHTTP HTTPS

### Changed
- **HTTPS layer rewritten from libcurl → WinHTTP.** `dev/src/helix_client.cpp`
  now uses the Win32 `winhttp` API directly. Eliminates the libcurl + vcpkg +
  OpenSSL dependency chain entirely. Plugin DLL stays smaller; CI no longer
  needs vcpkg bootstrap (~5 minutes saved per build).
- **Build matrix reduced to `windows-latest`.** Linux job dropped from
  `.github/workflows/build.yml`. The `.so` artifact is no longer produced.
- `dev/CMakeLists.txt`: links against `winhttp` + `ws2_32`. `find_package(CURL)`
  removed. Hard `if(NOT WIN32) message(FATAL_ERROR …)` gate.
- README + `dev/README.md` updated to reflect Windows-only status.

### Why
- The mod is consumed exclusively by Steam-Windows DF streamers; the Linux
  artifact had no users and cost a CI dependency footprint.
- vcpkg-pinning libcurl turned out to be the largest source of build flakiness
  during the v1.0-rc1 attempt (`run-vcpkg@v11` rejects branch refs, requires a
  full SHA1 — and any pin needs maintenance every few months).
- WinHTTP ships with every Windows install since Vista. Native Schannel TLS,
  native proxy detection, no third-party code to ship.

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
  - `helix_client.cpp` — WinHTTP wrapper (was libcurl in earlier RC) around `id.twitch.tv/oauth2/validate` and `api.twitch.tv/helix/polls` (create / get / end)
  - `oauth_server.cpp` — Authorization-Code flow with a `http://localhost:3000` listener, browser-launched
  - `token_store.cpp` — reads / writes `dfhack-config/DFxTwitch/config.json` (token fields only; preserves user-edited keys)
  - `event_queue.cpp` — thread-safe MPSC queue draining on the DFHack main-thread tick
  - `lua_api.cpp` — exposes `require('plugins.dfxtwitch')` with `connect`, `send_chat`, `auth_login`, `validate_token`, `poll_create / poll_get / poll_cancel`, `set_message_handler`, `set_poll_handler`, `status`
- **`dfxt-router.lua`** — chat-line dispatcher. Registers with `tw.set_message_handler`; performs role gate, per-user cooldown, and arg-shaping for every viewer command.
- **`dfxt-poll.lua`** — wraps `tw.poll_create` and the 5 s `tw.poll_get` polling loop. Single source of truth for "open a Twitch native poll, await a winner, fire callback".
- **`dfxt-auth.lua`** — one-shot OAuth runner; opens the browser, captures the code, persists tokens.
- **`dfxt-doctor.lua`** — health check (plugin loaded, config present, token valid, scopes correct, IRC connected).
- **`.github/workflows/build.yml`** — builds the plugin on Windows against a pinned DFHack tag and attaches the artifact to a draft Release on each tag.

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
