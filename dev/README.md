# `dfxtwitch.plug.dll` — DFHack plugin source

This directory builds the native plugin half of the mod. It does the things
DFHack's bundled Lua can't:

- HTTPS to Twitch Helix (**WinHTTP** — built into Windows since Vista)
- Twitch IRC over TCP (raw sockets)
- An OAuth Authorization-Code flow with a localhost:3000 listener

The Lua scripts in `../scripts_modinstalled/` call into this via
`require('plugins.dfxtwitch')`.

> **Windows-only.** The HTTPS layer is Win32 `winhttp.lib`, so there is no
> Linux build path. If you need a portable build, swap `helix_client.cpp` for
> a libcurl version — but that's out of scope for the v1.0 line.

> **Security:** Twitch chat uses WinHTTP WebSockets over TLS. The client
> secret and access/refresh tokens are encrypted with Windows DPAPI for the
> current Windows user. A clean Windows build now succeeds, but OAuth, DPAPI,
> Twitch networking, and in-game behavior have not been runtime-tested. Do not
> treat the plugin as release-verified.

## Pinned target

The selected build target is **DFHack 53.17-r1** for **DF 53.17**. A clean
Windows x64 Release build has succeeded against this version, but runtime
compatibility is not yet verified. The GitHub workflow still targets
DFHack 53.12-r1 and must not be used as evidence for a 53.17 release.

## Building (Windows, DFHack 53.17-r1)

Use an x64 Visual Studio 2022 C++ toolchain, CMake 3.21 or newer, Git with
submodule support, and MSYS2 Perl with `XML::LibXML` and `XML::LibXSLT`
available. The verified build used Perl 5.40.3 from MSYS2. Set up a fresh,
recursive DFHack checkout: DFHack's XML generator writes generated headers
into the source tree, so a separate binary build directory alone does not
make a reused checkout clean.

From PowerShell, adjust the source paths to your machine:

```powershell
$dfhack = 'C:\src\dfhack-53.17-r1'
$build = 'C:\build\dfxtwitch-53.17-r1'
git clone --recursive --branch 53.17-r1 https://github.com/DFHack/dfhack.git $dfhack
New-Item -ItemType Directory -Force "$dfhack\plugins\external\dfxtwitch"
Copy-Item 'F:\path\to\dfhack-twitch-integration\dev\*' `
  "$dfhack\plugins\external\dfxtwitch" -Recurse -Force
$env:PATH = 'C:\msys64\usr\bin;' + $env:PATH
perl -MXML::LibXML -MXML::LibXSLT -e "print qq(XML modules loaded\n)"
cmake -S $dfhack -B $build -G 'Visual Studio 17 2022' -A x64 `
  -DBUILD_PLUGINS=ON -DBUILD_SUPPORTED=OFF `
  -DBUILD_TESTS=OFF -DBUILD_DOCS=OFF `
  -DPERL_EXECUTABLE=C:/msys64/usr/bin/perl.exe
cmake --build $build --target dfxtwitch --config Release --parallel 4
```

The generated plugin is at
`$build\plugins\external\dfxtwitch\Release\dfxtwitch.plug.dll`. The supported
DFHack external-plugin mechanism discovers this folder; do not edit
`plugins/CMakeLists.txt`.

The clean build was verified with MSYS2 Perl because Strawberry Perl 5.40.5.1
reproducibly exited with `0xC0000005` during shutdown after producing the XML
outputs. The exact native cause is unknown; the Strawberry Perl installation
was not changed. The workaround is to select MSYS2 Perl and put its `usr\bin`
directory on `PATH`. Compilation does not establish runtime compatibility.

The standalone out-of-tree CMake fallback is experimental; use the DFHack
external-plugin build above to produce an installable plugin.

## Dependencies

- **WinHTTP + ws2_32** — both ship with Windows; linked in `CMakeLists.txt`.
  Nothing to install, no vcpkg.
- **nlohmann/json** — header-only, vendor it under
  `third_party/nlohmann/json.hpp`. CI grabs the latest release automatically.

## Files

| File | Purpose |
|---|---|
| `plugin.cpp`        | DFHack `plugin_init` / `plugin_shutdown` / `plugin_onupdate` glue |
| `lua_api.cpp`       | the `require('plugins.dfxtwitch')` surface |
| `irc_client.cpp`    | TCP IRC client + IRCv3 tag parser + role-from-badges |
| `helix_client.cpp`  | WinHTTP HTTPS helper + `validate / polls.create / polls.get / polls.end` |
| `oauth_server.cpp`  | localhost:3000 listener + token exchange |
| `token_store.cpp`   | reads/writes `dfhack-config/DFxTwitch/config.json` |
| `event_queue.cpp`   | thread-safe queue: workers push, main thread drains |
| `dfxt.hpp`          | internal header (declarations for all of the above) |

## Threading

- One **IRC** worker thread (raw TCP).
- WinHTTP calls are **synchronous on the calling Lua thread** — they happen
  during `plugin_eval_lua` from the streamer-side `dfxt-poll-tick` script,
  which DFHack runs on the main thread. That's fine: Helix calls are infrequent
  (≤ once per 5 s while a poll is open).
- Lua callbacks are dispatched **only on the main thread** from
  `plugin_onupdate` via `dispatch_pending()`.
