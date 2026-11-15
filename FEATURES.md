# DFHack Twitch Integration — Feature Inventory

Baseline recorded 2026-11-15. This inventory describes the current source and
documentation; it does not certify that the mod works at runtime. The
repository already contained local edits when this inventory was created.

No automated feature, Twitch integration, in-game, or clean-install tests have
been run. A clean Windows x64 Release build of `dfxtwitch` against DFHack
53.17-r1 has now succeeded, including XML code generation. This verifies
compilation only, not runtime compatibility. The GitHub workflow remains
pinned to DFHack 53.12-r1.

## Verification update (2026-11-15)

- The separate DFHack 53.17-r1 checkout is at the expected commit, has all 11
  submodules initialized, and remains clean. The older `C:\dfhack-src`
  checkout was left untouched.
- A separate source copy at DFHack commit
  `3bc63a220af608e1cf20b123dc45bc0a22e296ab` was used for the clean build.
  Its submodule contents came from the verified pinned commits; the original
  DFHack checkout and project working tree were not modified by the build.
- CMake 3.31.6 configured the `dfxtwitch` Visual Studio 2022 x64 Release
  target. The project's `nlohmann/json.hpp` matches the pinned 3.12.0 SHA-256.
- The previous Strawberry Perl reproduction used
  `%LOCALAPPDATA%\StrawberryPerl\perl\bin\perl.exe` (Perl 5.40.5.1), with
  XML::LibXML 2.0213 and XML::LibXSLT 2.003000. The modules load when
  Strawberry Perl's `c\bin` is added to `PATH`; `PERL5LIB` and `PERL5OPT` are
  unset.
- The exact DFHack `codegen.pl` command reproducibly exits with
  `0xC0000005`. It parses and transforms all 129 XML inputs, writes
  `codegen.out.xml`, reaches `exit` with error level 0, and then crashes during
  Perl shutdown. Windows Error Reporting identifies `ntdll.dll` at offset
  `0x000000000001a12d`; the specific native component causing the fault is
  not identified. Process-local `PERL_DESTRUCT_LEVEL` values 0, 1, and 2 did
  not prevent it. The exact native cause remains unknown; Perl was not
  repaired, replaced, or modified.
- A new CMake configure/build used MSYS2 Perl 5.40.3, with
  XML::LibXML 2.0210 and XML::LibXSLT 2.003000. CMake's actual absolute-path
  code-generation command completed successfully from a clean source copy.
- The `dfxtwitch` Release target completed successfully. The generated
  `codegen.out.xml` is 5,731,997 bytes, and the DLL exists at
  `F:\Df mods\dfhack-twitch-integration-build-53.17-clean\plugins\external\dfxtwitch\Release\dfxtwitch.plug.dll`
  (299,008 bytes). This is a clean build result, not a runtime test.
- Automated feature tests, Twitch integration tests, in-game tests, and
  clean-install tests remain unrun.

## Status totals

| Status | Count |
|---|---:|
| Implemented and tested | 0 |
| Implemented but untested | 7 |
| Partially implemented | 29 |
| Planned | 16 |
| Blocked | 0 |
| Deferred | 1 |
| Removed | 1 |
| **Total features** | **54** |

## Baseline and design decisions

| Feature | Description | Status | Priority | Evidence | Missing work |
|---|---|---|---|---|---|
| Supported DF/DFHack target | Build and test the selected release target, DF 53.17 / DFHack 53.17-r1. | **Partially implemented** | High | [`build.yml`](./.github/workflows/build.yml), [`dev/README.md`](./dev/README.md), [`README.md`](./README.md) | A clean Release build and code generation now succeed for 53.17-r1. Runtime compatibility and integration tests remain unverified, and the workflow still targets 53.12-r1; do not claim runtime support until the remaining checks pass. |
| OAuth architecture redesign | Reconsider the current Windows desktop authorization-code flow. | **Deferred** | Critical | [`oauth_server.cpp`](./dev/src/oauth_server.cpp), [`lua_api.cpp`](./dev/src/lua_api.cpp), [`config.example.json`](./config.example.json) | The owner chose to defer architecture changes until the existing flow is tested. Keep the current model for now; test it and revisit only with approval. |

## Native plugin and networking

| Feature | Description | Status | Priority | Evidence | Missing work |
|---|---|---|---|---|---|
| Secure Twitch chat connection | Connect to Twitch IRC through WinHTTP secure WebSockets and reconnect after failure. | **Implemented but untested** | High | [`irc_client.cpp`](./dev/src/irc_client.cpp): `connect_secure`, `worker` | Build and test TLS, host validation, handshake, reconnect, authentication rejection, and shutdown on the supported Windows/DFHack target. |
| IRC parsing, roles, and deduplication | Parse chat messages, extract Twitch badges, and ignore recently seen message IDs. | **Implemented but untested** | High | [`irc_client.cpp`](./dev/src/irc_client.cpp): `parse_line`, `role_from_badges`, `remember_message` | Add parser and role tests, including malformed, oversized, and unexpected frames. |
| Outbound chat queue and throttling | Bound queued messages and pace ordinary chat output. | **Implemented but untested** | High | [`irc_client.cpp`](./dev/src/irc_client.cpp): `queue_irc`, `send_worker`, `send_chat` | Test queue saturation, priority traffic, Unicode truncation, Twitch limits, disconnects, and message-delivery failures. |
| OAuth authorization callback | Open a browser, accept a localhost callback, validate state, and exchange the code. | **Partially implemented** | Critical | [`oauth_server.cpp`](./dev/src/oauth_server.cpp): `make_state`, `capture_code`, `login_blocking` | The flow blocks the calling Lua/game thread; validate callback edge cases and settle the desktop-app client/grant design. |
| OAuth token refresh and rotation | Refresh expired access tokens and persist rotated refresh tokens. | **Partially implemented** | Critical | [`oauth_server.cpp`](./dev/src/oauth_server.cpp): `refresh`; [`helix_client.cpp`](./dev/src/helix_client.cpp) | Refresh exists but is not connected to ordinary API requests. Add serialized refresh, 401 recovery, rotation persistence, failure recovery, and tests. |
| DPAPI credential storage and migration | Protect client secret and OAuth tokens for the current Windows user; migrate legacy plaintext config. | **Implemented but untested** | Critical | [`token_store.cpp`](./dev/src/token_store.cpp): `protect_credentials`, `unprotect_credentials`, `load_config`, `save_config` | Build and test encryption/decryption, migration, corrupt data, failed writes, and recovery under a different Windows profile. |
| Twitch Helix poll API | Create, retrieve, and end native Twitch polls. | **Partially implemented** | High | [`helix_client.cpp`](./dev/src/helix_client.cpp): `create_poll`, `get_poll`, `end_poll` | `http::request` drops URL query parameters, so `get_poll` omits its required `broadcaster_id` and `id`. Calls are also synchronous. Preserve query strings, then add request lifecycle integration with token refresh, rate-limit handling, cancellation, and mocked API tests. |
| Plugin lifecycle and thread-to-Lua dispatch | Run IRC networking off-thread and dispatch queued events on DFHack's main thread. | **Partially implemented** | Critical | [`plugin.cpp`](./dev/src/plugin.cpp), [`event_queue.cpp`](./dev/src/event_queue.cpp), [`lua_api.cpp`](./dev/src/lua_api.cpp) | `evq::push` allows 4097 queued events despite the stated 4096 cap. Correct and test queue overflow, callback lifetime, plugin disable/unload, worker cancellation/join, and repeated load/unload. Keep all game/Lua access on the main thread. |

## Chat commands and gameplay

| Feature | Description | Status | Priority | Evidence | Missing work |
|---|---|---|---|---|---|
| Command routing, permissions, and cooldowns | Map Twitch commands to scripts and enforce role tiers and per-user cooldowns. | **Partially implemented** | High | [`dfxt-router.lua`](./scripts_modinstalled/dfxt-router.lua), [`dfxt-common.lua`](./scripts_modinstalled/dfxt-common.lua) | Errors are swallowed; arguments are lowercased; configured role aliases are not applied. Validate arguments and permissions before execution and test all routes. |
| Configured role aliases | Map Twitch role names to the project's tier ladder. | **Partially implemented** | Medium | [`config.example.json`](./config.example.json): `role_aliases`; [`dfxt-common.lua`](./scripts_modinstalled/dfxt-common.lua): `role_meets` | The aliases setting is not consumed. Either implement and test the documented behavior or accurately document the fixed mapping. |
| Claim an existing citizen | Assign an unclaimed citizen to a viewer and save the viewer-to-unit association. | **Implemented but untested** | High | [`dfxt-claim.lua`](./scripts_modinstalled/dfxt-claim.lua): FCFS branch; [`dfxt-common.lua`](./scripts_modinstalled/dfxt-common.lua): `unclaimed_citizens` | Test duplicate, invalid, dead, unavailable, and reload cases; verify the nickname/history behavior in-game. |
| Claim a future migrant | Queue a viewer for the next natural migrant wave. | **Partially implemented** | High | [`dfxt-claim.lua`](./scripts_modinstalled/dfxt-claim.lua): migrant branch; [`SPEC.md`](./SPEC.md) | The request is queued but no arrival handler consumes it or renames an arriving unit. |
| Claim an enemy unit | Queue a moderator-approved viewer to appear as a future enemy. | **Partially implemented** | High | [`dfxt-claim.lua`](./scripts_modinstalled/dfxt-claim.lua): enemy branch; [`SPEC.md`](./SPEC.md) | The request is queued but no safe, verified spawn/arrival implementation exists. Define intended behavior and safety before attempting it. |
| Viewer status and available-citizen commands | Report a viewer's claim state and summarize unclaimed citizens. | **Implemented but untested** | Medium | [`dfxt-status.lua`](./scripts_modinstalled/dfxt-status.lua) | Test stale records, deaths, and output against live fortress data. |
| Citizen information commands | Report life/health, skills, kills, relatives, and preferences. | **Partially implemented** | High | [`dfxt-check.lua`](./scripts_modinstalled/dfxt-check.lua) | Several outputs are counts or raw IDs rather than the documented full information; verify data fields and avoid misleading claims. |
| Utility commands | Report active mods and basic fortress status. | **Implemented but untested** | Low | [`dfxt-mods.lua`](./scripts_modinstalled/dfxt-mods.lua), [`dfxt-ping.lua`](./scripts_modinstalled/dfxt-ping.lua) | Test against supported DFHack APIs and Twitch output limits. |
| Viewer command help | Explain the commands and tiers available to viewers. | **Partially implemented** | Medium | [`dfxt-help.lua`](./scripts_modinstalled/dfxt-help.lua), [`SPEC.md`](./SPEC.md) | The help output omits documented commands and does not fully reflect permission tiers. |
| Squad join and leave | Add a claimed dwarf to or remove them from a selected squad. | **Partially implemented** | High | [`dfxt-squad.lua`](./scripts_modinstalled/dfxt-squad.lua) | Directly edits squad position occupants without verifying a supported high-level API or all required game state. Test legal membership, capacity, and reload. |
| Temporary squad leave and rejoin | Remove a dwarf temporarily and restore the prior squad position after a requested duration. | **Partially implemented** | Medium | [`dfxt-leave.lua`](./scripts_modinstalled/dfxt-leave.lua), [`dfxt-overlay.lua`](./scripts_modinstalled/dfxt-overlay.lua) | Uses a year-local tick for the deadline, accepts unbounded days, and edits squad occupants directly. Test year transitions and reload. |
| Religion preference metadata | Record viewer deity/entity-religion preferences and list known religions. | **Partially implemented** | Medium | [`dfxt-religion.lua`](./scripts_modinstalled/dfxt-religion.lua), [`README.md`](./README.md) | The scripts report that viewers worship or joined a religion although only mod metadata changes. Fix the claims and test persistence. |
| Apply actual in-game religion changes | Change a dwarf's actual deity worship or entity-religion membership. | **Planned** | Medium | [`SPEC.md`](./SPEC.md), [`dfxt-religion.lua`](./scripts_modinstalled/dfxt-religion.lua) | Verify safe supported APIs for the target DFHack version. Do not claim completion or mutate raw history data without verification. |

## Petitions and polls

| Feature | Description | Status | Priority | Evidence | Missing work |
|---|---|---|---|---|---|
| Petition discovery and queue | Find unresolved agreements and retain petition IDs for later handling. | **Partially implemented** | High | [`dfxt-petitions.lua`](./scripts_modinstalled/dfxt-petitions.lua): `scan`, `get_agreements` | The scan does not robustly filter agreement types or prove each ID is a supported petition. Test stale and resolved IDs. |
| Start petition votes from chat | Let viewers initiate or start a petition vote using the documented command. | **Partially implemented** | High | [`dfxt-petitions.lua`](./scripts_modinstalled/dfxt-petitions.lua), [`config.example.json`](./config.example.json) | Queue notices say `!petitions`, but that command is absent from the command map/router. The overlay instead starts polls automatically; define and implement one consistent workflow. |
| Twitch petition poll lifecycle | Open a poll, retrieve the result, and avoid treating failed/tied/cancelled polls as approval. | **Partially implemented** | High | [`dfxt-poll.lua`](./scripts_modinstalled/dfxt-poll.lua), [`dfxt-petitions.lua`](./scripts_modinstalled/dfxt-petitions.lua) | Poll state is transient; failed status checks can leave polls unresolved, and cancellation errors are ignored. Test save/reload and API failures. |
| Streamer approval and rejection | Keep the final in-game petition decision under streamer control. | **Partially implemented** | Critical | [`dfxt-petitions.lua`](./scripts_modinstalled/dfxt-petitions.lua), [`SPEC.md`](./SPEC.md) | Approval/rejection remains manual; rejection is explicitly a reminder to click Reject. Preserve this gate and make the required action clear. |
| Unsupported petition types | Notify the streamer about petition types that are not handled by viewer voting. | **Partially implemented** | High | [`SPEC.md`](./SPEC.md), [`dfxt-petitions.lua`](./scripts_modinstalled/dfxt-petitions.lua) | Implement reliable type filtering and ensure unsupported types never enter an inappropriate poll. |

## Events and event safety

| Feature | Description | Status | Priority | Evidence | Missing work |
|---|---|---|---|---|---|
| Event scheduler and voting | Select eligible events, open a Twitch poll, and record its result. | **Partially implemented** | High | [`dfxt-events.lua`](./scripts_modinstalled/dfxt-events.lua), [`dfxt-overlay.lua`](./scripts_modinstalled/dfxt-overlay.lua) | Poll winners are announced but do not perform the specified gameplay effects. Test scheduling, concurrent polls, stale state, and failure paths. |
| Weather event effect | Apply the winning weather choice to the fortress. | **Planned** | Medium | [`SPEC.md`](./SPEC.md), [`dfxt-events.lua`](./scripts_modinstalled/dfxt-events.lua): `weather` | No verified gameplay effect is implemented. Verify the target-version API and map limitations before enabling. |
| Cheers/mood event effect | Announce a selected citizen and apply the specified mood effect. | **Planned** | Low | [`SPEC.md`](./SPEC.md), [`dfxt-events.lua`](./scripts_modinstalled/dfxt-events.lua): `cheers` | Neither the full selection behavior nor the mood effect is implemented. |
| Squad rename event effect | Rename a selected squad after a poll. | **Planned** | Low | [`SPEC.md`](./SPEC.md), [`dfxt-events.lua`](./scripts_modinstalled/dfxt-events.lua): `name_squad` | Only placeholder choices exist; no rename handler is implemented. |
| Fort slogan event effect | Collect/vote on a fort slogan and show it in the overlay. | **Planned** | Low | [`SPEC.md`](./SPEC.md), [`dfxt-events.lua`](./scripts_modinstalled/dfxt-events.lua): `name_fort` | Free-response collection, vote, and overlay display are not implemented. |
| Migrant-race event effect | Apply a poll winner to the next migrant wave. | **Planned** | High | [`SPEC.md`](./SPEC.md), [`dfxt-events.lua`](./scripts_modinstalled/dfxt-events.lua): `migrants_race` | Choices are generated, but no verified mechanism changes the next wave. |
| Caravan event effect | Cause a caravan to arrive after the poll. | **Planned** | Medium | [`SPEC.md`](./SPEC.md), [`dfxt-events.lua`](./scripts_modinstalled/dfxt-events.lua): `caravan` | No effect is implemented; verify a supported target-version mechanism before enabling. |
| Bard event effect | Add or welcome a bard based on the poll. | **Planned** | Low | [`SPEC.md`](./SPEC.md), [`dfxt-events.lua`](./scripts_modinstalled/dfxt-events.lua): `bard` | No effect is implemented. |
| Ambush/siege event effects | Trigger the selected hostile event after a poll. | **Planned** | High | [`SPEC.md`](./SPEC.md), [`dfxt-events.lua`](./scripts_modinstalled/dfxt-events.lua): `ambush`, `siege_small` | No effect is implemented. Keep disabled unless verified, opt-in, and tested in a disposable fortress. |
| Forgotten-beast event effect | Create or wake a forgotten beast after a poll. | **Planned** | High | [`SPEC.md`](./SPEC.md), [`dfxt-events.lua`](./scripts_modinstalled/dfxt-events.lua): `forgottenbeast` | No effect is implemented. The documented `modtools/create-unit` tool is marked unavailable; do not rely on it as a dependable path. |
| Flood-room event effect | Apply the specified flood effect after a poll. | **Planned** | High | [`SPEC.md`](./SPEC.md), [`dfxt-events.lua`](./scripts_modinstalled/dfxt-events.lua): `floodroom` | No effect is implemented. Avoid unsafe map mutation; verify a safe API and containment/stop behavior. |
| Existing event safety gates | Enforce dangerous-bucket opt-in, cooldowns, and siege/invader checks. | **Partially implemented** | Critical | [`dfxt-events.lua`](./scripts_modinstalled/dfxt-events.lua): `blocked_for_bc`, `open_poll` | Bucket C defaults off, but threat detection is incomplete and effects do not exist. Test all gates and invalid/unknown event names. |
| Recent-death and megabeast/titan restrictions | Block dangerous events when a citizen recently died or a dangerous creature is present. | **Planned** | Critical | [`SPEC.md`](./SPEC.md), [`dfxt-events.lua`](./scripts_modinstalled/dfxt-events.lua) | No recent-death tracking or reliable titan/megabeast detection is established. Unknown state must fail closed. |
| Bucket D | Additional event bucket. | **Removed** | Low | [`SPEC.md`](./SPEC.md): “Bucket D — Not implemented. Removed by spec.” | No work planned; retain this record so removal is visible. |

## Overlay, configuration, persistence, and diagnostics

| Feature | Description | Status | Priority | Evidence | Missing work |
|---|---|---|---|---|---|
| Twitch chat overlay | Display recent chat messages in the DF screen. | **Partially implemented** | Medium | [`dfxt-overlay.lua`](./scripts_modinstalled/dfxt-overlay.lua), [`dfxt-router.lua`](./scripts_modinstalled/dfxt-router.lua) | The overlay buffer exists, but the router does not call `dfxt_push_chat_line`; test limits, text safety, and reload. |
| Poll/event/leave heartbeat | Drive poll checks, petition scans, event scheduling, and leave timers. | **Partially implemented** | High | [`dfxt-overlay.lua`](./scripts_modinstalled/dfxt-overlay.lua) | Many failures are silently swallowed with `pcall`; test timing, errors, pause/unload, and stale polls. |
| Configuration loading and validation | Load config, apply defaults, validate values, and preserve user settings. | **Partially implemented** | High | [`dfxt-common.lua`](./scripts_modinstalled/dfxt-common.lua), [`token_store.cpp`](./dev/src/token_store.cpp), [`config.example.json`](./config.example.json) | Lua silently falls back on invalid JSON and performs weak type/range validation. Avoid success-shaped defaults and test migrations/failures. |
| Persistent state and fortress isolation | Persist claims, queues, event budgets, and poll state across saves without cross-fortress leakage. | **Partially implemented** | Critical | [`dfxt-common.lua`](./scripts_modinstalled/dfxt-common.lua): `persist`; [`SPEC.md`](./SPEC.md) | Verify `GlobalTable` scope, separate-fortress isolation, save/reload, plugin restart, and recovery. Poll state is not fully reconciled with Twitch. |
| Logging and diagnostics | Provide useful status and errors without exposing credentials. | **Partially implemented** | Medium | [`dfxt-doctor.lua`](./scripts_modinstalled/dfxt-doctor.lua), [`dfxt-common.lua`](./scripts_modinstalled/dfxt-common.lua): `say`, `pet_log`; [`lua_api.cpp`](./dev/src/lua_api.cpp) | Several Lua and API errors are swallowed; diagnostic output and affiliate checks need accuracy and privacy tests. |

## Build, tests, compatibility, and documentation

| Feature | Description | Status | Priority | Evidence | Missing work |
|---|---|---|---|---|---|
| Reproducible plugin build and release workflow | Build the Windows plugin against a pinned DFHack checkout and produce a release artifact. | **Partially implemented** | Critical | [`build.yml`](./.github/workflows/build.yml), [`dev/CMakeLists.txt`](./dev/CMakeLists.txt) | A clean `dfxtwitch` Release build against 53.17-r1 generated headers and produced a DLL using MSYS2 Perl 5.40.3. Strawberry Perl still crashes during shutdown with `0xC0000005`; its native cause is unknown. The workflow remains pinned to 53.12-r1, and a CI build/release artifact for the selected target is not verified. Runtime and feature tests are separate and remain unrun. |
| Automated tests | Test native networking/queues, Lua routing, permissions, config, and persistence. | **Planned** | High | No test files or test runner are present in the repository. | Add focused C++ and Lua tests and wire them into CI. |
| Twitch and DFHack integration tests | Test plugin loading, auth, chat, Helix polls, and failure paths against real supported services. | **Planned** | High | [`dev/README.md`](./dev/README.md), [`README.md`](./README.md) | No current tests were run. Use a dedicated test account and report unperformed checks as NOT TESTED. |
| Disposable-fortress and clean-install tests | Verify gameplay effects, save/reload, shutdown, packaging, and documented Windows installation. | **Planned** | High | [`SPEC.md`](./SPEC.md), [`dev/README.md`](./dev/README.md) | No in-game or clean-install test has been performed. |
| Compatibility and distribution support | Declare and verify supported DF/DFHack releases and installation distributions. | **Partially implemented** | High | [`README.md`](./README.md), [`info.txt`](./info.txt), [`build.yml`](./.github/workflows/build.yml) | A clean compile is verified for 53.17-r1, but runtime compatibility is not. The workflow remains pinned to 53.12-r1, and no Steam/itch.io/Classic installation has been tested. |
| User documentation | Explain real functionality, permissions, installation, config, limitations, and troubleshooting. | **Partially implemented** | Medium | [`README.md`](./README.md), [`SPEC.md`](./SPEC.md), [`dev/README.md`](./dev/README.md), [`dfxt-help.lua`](./scripts_modinstalled/dfxt-help.lua) | Several spec claims exceed implementation; config examples and command help need alignment with tested behavior. |
| Recovery, migration, and uninstall guide | Explain token recovery, config migration, revocation, and safe removal. | **Planned** | Medium | [`README.md`](./README.md), [`dev/README.md`](./dev/README.md) | Document DPAPI profile limitations, legacy-token migration, troubleshooting, and uninstall/revocation steps. |

## Planned features

The planned entries above are documented or implied features with no completed
gameplay effect. They must not be reported as working until their APIs,
permissions, safety rules, and acceptance tests are verified. The deferred
OAuth redesign and removed Bucket D entry are excluded from the planned count.

## Owner choices recorded

1. Target DFHack 53.17-r1 / DF 53.17.
2. Defer OAuth architecture changes until the current flow has been tested.
3. Keep the existing Windows-only scope unless a separate portability decision
   is made. Do not remove or claim support for existing features without
   explicit owner approval.
