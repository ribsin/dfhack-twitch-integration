# `dfxtwitch.plug.dll` — DFHack plugin source

This directory builds the native plugin half of the mod. It does the things
DFHack's bundled Lua can't:

- HTTPS to Twitch Helix (libcurl)
- Twitch IRC over TCP (raw sockets)
- An OAuth Authorization-Code flow with a localhost:3000 listener

The Lua scripts in `../scripts_modinstalled/` call into this via
`require('plugins.dfxtwitch')`.

## Pinned target

This repo's `v1.0` line builds against **DFHack 53.12-r1** (which targets
**DF 53.12**). If you're running a different DFHack release, change the tag
in the steps below *and* in `.github/workflows/build.yml` (`DFHACK_TAG`).

## Building (in-tree against DFHack)

This is the supported path. The plugin is built from inside a DFHack source
checkout against the same DFHack version your DF install runs.

```bash
git clone --recursive --branch 53.12-r1 https://github.com/DFHack/dfhack.git
cd dfhack
# copy (or symlink) this dev/ folder into plugins/dfxtwitch
cp -r ../dfhack-twitch-integration/dev plugins/dfxtwitch
echo 'add_subdirectory(dfxtwitch)' >> plugins/CMakeLists.txt
# vendor nlohmann/json (header-only)
mkdir -p plugins/dfxtwitch/third_party/nlohmann
curl -L -o plugins/dfxtwitch/third_party/nlohmann/json.hpp \
  https://github.com/nlohmann/json/releases/latest/download/json.hpp
# build
cmake -B build -G Ninja -DBUILD_PLUGINS=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build --target dfxtwitch
```

Result: `build/plugins/dfxtwitch/dfxtwitch.plug.dll` (Windows) or
`.plug.so` (Linux). Drop it into `<DF>/hack/plugins/`.

### Windows note

Use the **x64 Native Tools Command Prompt for VS 2022** so MSVC is on
`PATH`, install vcpkg, and pass:
`-DCMAKE_TOOLCHAIN_FILE=<vcpkg>/scripts/buildsystems/vcpkg.cmake -DVCPKG_TARGET_TRIPLET=x64-windows-static`
to the configure step. CI does exactly this — see `.github/workflows/build.yml`.

## Building (out-of-tree, for CI)

```bash
cmake -S dev -B dev/build -DDFHACK_SOURCE_DIR=/path/to/dfhack
cmake --build dev/build
```

This produces a stand-alone shared library; useful for tinkering but you'll
still need DFHack's exported headers from a real source tree.

## Dependencies

- **libcurl** — fetched via vcpkg in CI, or any system libcurl on Linux
- **nlohmann/json** — header-only, vendor it under `third_party/nlohmann/json.hpp`

CI handles both for you (see `.github/workflows/build.yml`).

## Files

| File | Purpose |
|---|---|
| `plugin.cpp`        | DFHack `plugin_init` / `plugin_shutdown` / `plugin_onupdate` glue |
| `lua_api.cpp`       | the `require('plugins.dfxtwitch')` surface |
| `irc_client.cpp`    | TCP IRC client + IRCv3 tag parser + role-from-badges |
| `helix_client.cpp`  | libcurl HTTPS helper + `validate / polls.create / polls.get / polls.end` |
| `oauth_server.cpp`  | localhost:3000 listener + token exchange |
| `token_store.cpp`   | reads/writes `dfhack-config/DFxTwitch/config.json` |
| `event_queue.cpp`   | thread-safe queue: workers push, main thread drains |
| `dfxt.hpp`          | internal header (declarations for all of the above) |

## Threading

- One **IRC** worker thread (raw TCP).
- libcurl calls are **synchronous on the calling Lua thread** — they happen
  during `plugin_eval_lua` from the streamer-side `dfxt-poll-tick` script,
  which DFHack runs on the main thread. That's fine: Helix calls are infrequent
  (≤ once per 5 s while a poll is open).
- Lua callbacks are dispatched **only on the main thread** from
  `plugin_onupdate` via `dispatch_pending()`.
