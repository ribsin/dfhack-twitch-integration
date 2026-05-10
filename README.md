# DFHack Twitch Integration

Lets a Twitch chat interact with a Dwarf Fortress fortress through DFHack.

- Viewers can claim a dwarf with `!join` and check on it with `!me`, `!check`, `!skills`, …
- Chat votes on real in-game **petitions** (Location/Residency/Citizenship) when there's no siege happening.
- Plugin-driven **events** nudge the world: weather changes, surprise caravans, voted-on migrant races, optional rare hostilities.
- Roles are honored: streamer / mod / VIP / subscriber / any.

This repo is **the mod** — Lua scripts that DFHack runs. The mod works today with an external Twitch bot that just routes chat into `dfhack-run`. A native DFHack plugin (separate download, GitHub-only) is on the roadmap and will replace the external bot.

## Status

`v1.0-alpha` — implementing the spec in `SPEC.md`. See `CHANGELOG.md` for what's landed.

## Install

1. Subscribe on Steam Workshop (when published) or copy the `dfhack-twitch-integration/` folder into:
   ```
   <DF>/data/installed_mods/
   ```
2. Generate a new world with the mod active (or add it to an existing world via `data/installed_mods` → "Add mod to save").
3. Copy `dfhack-config/DFxTwitch/config.example.json` to `config.json` and fill in your channel, bot username, and OAuth token. (See `config.example.json` for scope notes.)
4. Until the native plugin ships, run an external bot (any Twitch chat bot you trust) that pipes commands through `dfhack-run`. Example: a chat message `!check Bob` becomes `dfhack-run dfxt-check --u Bob --role any --t alive`.

## Companion plugin (later)

A C++ DFHack plugin is planned that talks Twitch IRC + Helix directly, making the external bot unnecessary. The plugin source will live in this repo's `dev/` folder. Distribution will be a per-DFHack-version zip on GitHub Releases (Steam Workshop does not allow binary plugins).

## Documentation

- `SPEC.md` — frozen behavior spec for v1.0-alpha
- `CHANGELOG.md` — what's been built so far
- `LICENSE` — MIT

## Author

Ribsin
