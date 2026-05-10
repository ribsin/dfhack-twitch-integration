# Changelog

## v1.0-rc10 — Plugin: fix DFHack 53.x API drift (Lua 5.3, Core::getLuaState, NOMINMAX)

### Fixed
- **First CI run that compiled the plugin's own source surfaced four
  unrelated mistakes from the v1.0-rc1 era**, all of which had been masked
  by rc3..rc8's toolchain breakage. Every fix is small; the *combination*
  is what was hidden.

  1. **`dev/src/lua_api.cpp:77` — `lua_objlen` does not exist in Lua 5.3.**
     DFHack ships Lua 5.3, which renamed `lua_objlen` to `lua_rawlen`.
     We were using the Lua 5.1/5.2 spelling. Replaced.
  2. **`dev/src/lua_api.cpp:160` — `Lua::Core::State` does not exist in
     DFHack 53.x.** That namespace-scope lua_State variable was removed;
     the canonical accessor is now `Core::getInstance().getLuaState()`.
     Every error from line 164 onward (`StackUnwinder` arg, `lua_pushstring`
     arg, `lua_rawgeti` arg, etc.) was a downstream casualty of `auto* L`
     becoming `<error type>`. Switched to `Core::getInstance().getLuaState()`.
  3. **`dev/src/lua_api.cpp:171, :184` — `Console` is not a smart pointer.**
     We were calling `Core::getInstance().getConsole().get()` as if it were
     a `shared_ptr<Console>`. It returns `Console&` (a `color_ostream`
     subclass) directly. Refactored `dispatch_pending` to take a
     `color_ostream& out` plumbed through from `plugin_onupdate`, which is
     both correct *and* avoids a global lookup on the tick path.
  4. **`dev/src/plugin.cpp:50, :54` — `DFHACK_LUA_END` lives in
     `PluginLua.h`, not `PluginManager.h`.** That header is mentioned in
     `plugins/examples/skeleton.cpp` as commented-out, with the note "this
     include is only required if the plugin is going to bind to Lua events,
     functions, or commands". We bind Lua, so we need it. Added
     `#include "PluginLua.h"`. The macros `DFHACK_PLUGIN_LUA_FUNCTIONS`,
     `DFHACK_PLUGIN_LUA_COMMANDS`, and `DFHACK_LUA_END` (which expands to
     `{ NULL, NULL }`) all live there.
  5. **`dev/src/plugin.cpp` — `plugin_eval_lua` is not a real DFHack hook.**
     We had an `extern "C"` `plugin_eval_lua` exported as the registration
     point. DFHack does not call it. Replaced with explicit registration
     from `plugin_init`: fetch the core Lua state via
     `Core::getInstance().getLuaState()` and call `register_lua(L)` directly.
     This uses the same code path scripts will use when they
     `require('plugins.dfxtwitch')`, since both share the core state.
  6. **`dev/src/irc_client.cpp:117` — Windows `<windows.h>` `min`/`max`
     macros clobber `std::min`.** The C2589 / C2059 cascade was
     `std::min(backoff * 2, 60)` being preprocessed into
     `std::(((backoff*2)<(60))?(backoff*2):(60))` — illegal token after
     `::`. Added `#define NOMINMAX` *before* the `<winsock2.h>` /
     `<ws2tcpip.h>` includes, with a comment so a future merge doesn't
     undo it.

### Changed
- `dev/src/lua_api.cpp`:
  - `lua_objlen(L, 2)` → `lua_rawlen(L, 2)`.
  - `dispatch_pending()` → `dispatch_pending(color_ostream& out)`.
  - `auto* L = Lua::Core::State` → `auto* L = DFHack::Core::getInstance().getLuaState()`.
  - `Lua::SafeCall(*Core::getInstance().getConsole().get(), ...)` →
    `Lua::SafeCall(out, ...)` (uses the plumbed-through ostream).
- `dev/src/plugin.cpp`:
  - `#include "PluginLua.h"` added.
  - `plugin_eval_lua` extern removed.
  - `plugin_init` now calls `register_lua(Core::getInstance().getLuaState())`.
  - `plugin_onupdate` now passes `out` through to `dispatch_pending`.
- `dev/src/irc_client.cpp`:
  - `#define NOMINMAX` (guarded with `#ifndef`) before any Win32 include.
  - `#include <algorithm>` added explicitly — relying on transitive include
    via `<atomic>` is fragile and the `std::min` call site is the proximate
    user.

### Notes
- Lua scripts in `scripts_modinstalled/` are unchanged.
- `helix_client.cpp` and `oauth_server.cpp` compiled cleanly in the rc9 CI
  run — they don't include winsock2 the same way, so the NOMINMAX issue
  didn't materialise there. Leaving them alone for now; if a future Win32
  header pull-in surfaces the same `min` macro problem, fix in place.
- This is the first rc that should produce a `dfxtwitch.plug.dll` artifact.

## v1.0-rc9 — Plugin: require C++20 (DFHack 53.x uses concepts + `requires`)

### Fixed
- **`dev/CMakeLists.txt` was forcing `CMAKE_CXX_STANDARD 17` while DFHack
  53.x's public headers require C++20.** rc8 finally got CI past Perl, only
  to faceplant on the very next stage — compiling the plugin itself. The
  build emitted `STL4038` (`<concepts> requires C++20 or later`) followed
  by a cascade of every C++20 feature DFHack uses:
    - `MiscUtils.h:325` — `std::invocable` (C++20 concepts library)
    - `DataDefs.h:575` — `std::assignable_from` (C++20)
    - `DataDefs.h:607` — bare `requires` keyword (C++20)
    - `BitArray.h:605` — `std::bidirectional_iterator` (C++20 iterator concepts)
    - `plugin.cpp:49` — `DFHACK_LUA_END` undefined (lives behind a
      `#if __cpp_concepts` block in DFHack's headers, invisible in C++17)
    - `LuaTools.h:43` — `lua.h` not found (cascading: when concepts blow up
      the include chain stops short, but it's also a real propagation gap
      worth pinning).

  We were the *only* plugin in the build forcing 17. Every other DFHack
  plugin inherits the project's C++20 default. This one line was lying
  about its requirements since the very first commit.

### Changed
- `dev/CMakeLists.txt`:
  - **`CMAKE_CXX_STANDARD 17` → `20`.** With a comment explaining exactly
    which DFHack headers need it, so a future rebase doesn't quietly
    revert this.
  - **In-tree branch now links `lua`** in `DFHACK_PLUGIN(... LINK_LIBRARIES
    winhttp ws2_32 lua)`. The `lua` CMake target's INTERFACE include dir
    propagates `lua.h` into the plugin without us hard-coding the path.
    Belt-and-braces against the propagation gap that may have contributed
    to the `lua.h: No such file or directory` error.
  - Out-of-tree branch unchanged — it already had
    `${DFHACK_SOURCE_DIR}/depends/lua/include`.

### Notes
- Plugin source is unchanged. This is a build-system fix.
- Lua scripts in `scripts_modinstalled/` are unchanged.
- This unblocks the actual code from compiling for the first time in CI.
  Expect the *next* CI run to surface real plugin-source errors (if any) —
  not infrastructure ones. We are finally past the toolchain.

## v1.0-rc8 — CI: run Perl verify under cmd (Git Bash was shadowing Strawberry)

### Fixed
- **`shell: bash` on Windows runners uses Git for Windows' bundled
  `/usr/bin/perl`**, which is on `$PATH` *before* the runner image's
  Strawberry Perl. That bundled perl has a near-empty `@INC`
  (`/usr/lib/perl5/site_perl`, `/usr/share/perl5/core_perl`, …) and ships
  none of the CPAN modules we need. rc7's verify step ran under
  `shell: bash` and failed:
  `Can't locate XML/LibXML.pm in @INC` — exit 2. The XML modules *are* on
  the image's Strawberry Perl; we were just calling the wrong `perl`.
- **This is also the actual root cause of rc3..rc5.** Every `cpanm`
  invocation we ran was under `shell: bash`, so it executed Git's bundled
  perl (and, occasionally, Git's bundled cpanm script run under that perl,
  which is why `@INC` looked Linux-shaped in the rc3 error output). The
  "broken fatpacked cpanm", "missing `ExtUtils::Manifest`", and "MakeMaker
  self-upgrade circle" were all symptoms of running cpanm in an environment
  that *legitimately* had neither the modules nor the toolchain to fix
  itself. We were never reaching Strawberry. Plugin source is unchanged.

### Changed
- `.github/workflows/build.yml`:
  - Verify step switched from `shell: bash` → **`shell: cmd`**. CMake
    spawns `perl` via `cmd.exe` using the system PATH (which prefers
    Strawberry), so verifying under `cmd` checks the *exact* perl codegen
    will use.
  - Added `where perl` as a diagnostic — if the runner image's PATH order
    ever shifts, the log will show which perl was actually invoked
    instead of leaving us guessing for four iterations.

## v1.0-rc7 — CI: stop installing Perl entirely (DFHack doesn't, neither should we)

### Fixed
- **CI Perl install step was always vestigial; removing it ends the rc3..rc6
  iteration loop.** Confirmed by reading DFHack's own `build-windows.yml`
  (byte-identical between `master` and the `53.12-r1` tag we pin): DFHack's
  workflow has **zero** Perl install steps. It runs on `windows-2022` and
  trusts the runner image's preinstalled Strawberry Perl, which still bundles
  `XML::LibXML` + `XML::LibXSLT` for codegen. Every cpanm / `shogo82148/...` /
  `choco install strawberryperl` workaround we attempted was invoking
  machinery the upstream project never invokes — and was the *only* thing
  failing across rc3–rc6:
    - rc3: image's preinstalled fatpacked `cpanm` is broken
      (`CPAN::Meta::Prereqs` import error). We hit it because we *called* cpanm.
    - rc4: missing `ExtUtils::Manifest` in `@INC`. We hit it because we
      *called* cpanm.
    - rc5: cpanm circular-resolution bailout (`MakeMaker` upgrade vs. `Pod::Man`
      install). We hit it because we *called* cpanm.
    - rc6: `choco install strawberryperl` returned MSI 1603 — Windows
      Installer refuses a sideways install over the runner image's
      preinstalled Strawberry. We hit it because we tried to *replace* the
      preinstalled Perl that already had the modules we needed.

  Plugin source is unchanged.

### Changed
- `.github/workflows/build.yml`:
  - **Removed** the entire Perl install step (the `choco install strawberryperl`
    block from rc6, and by extension all of rc3–rc5's cpanm machinery).
  - **Kept** a fast-fail verify step (`perl -V:version` +
    `perl -MXML::LibXML -e ...` + `perl -MXML::LibXSLT -e ...`). It costs ~50ms
    and surfaces a clear error here if a future runner image ever drops the
    bundled modules, rather than letting DFHack codegen blow up 30s later
    with a less obvious message.

## v1.0-rc6 — CI: skip cpanm; install full Strawberry Perl via Chocolatey

### Fixed
- **CI Perl step kept hitting cpanm circular-resolution bailouts.** rc5's
  `--installdeps ExtUtils::MakeMaker` reproduced the same cycle one step
  further out: cpanm Configured `ExtUtils::MakeMaker-7.78`, started
  installing `Pod::Man` (`podlators-v6.0.2`), and bailed out with
  `Module 'ExtUtils::MakeMaker' is not installed` — its safety mechanism
  refusing to recurse into a module that's already in flight in the parent
  resolution. Plugin source is unchanged.

### Changed
- `.github/workflows/build.yml`:
  - **Removed** `shogo82148/actions-setup-perl` and the entire `cpanm` step.
  - **Added** a Chocolatey install of the **full** Strawberry Perl 5.38.2.2
    distribution (`choco install strawberryperl --version=5.38.2.2 -y
    --no-progress --force --allow-downgrade`). Strawberry's Standard
    distribution bundles `XML::LibXML` + `XML::LibXSLT` *prebuilt*, along
    with the `Alien::Libxml2`, `ExtUtils::MakeMaker`, `ExtUtils::Manifest`,
    and `Pod::Man` chain — so cpanm never has to resolve any of it. This
    sidesteps every Perl bug we've hit since rc3 in one move.
  - **Added** a verification step (`perl -MXML::LibXML -e ...`) that fails
    fast with a clear message if a future Strawberry drops the bundled
    modules, instead of letting DFHack's codegen explode two steps later.

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
