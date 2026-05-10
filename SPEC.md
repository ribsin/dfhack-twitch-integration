# DFHack Twitch Integration — Specification v1.0-alpha

> **Author:** Ribsin   **License:** MIT   **Status:** Frozen for v1.0-alpha implementation.

This document is the source of truth for what the mod must do. Any change to behavior gets reflected here first, then in code.

---

## 0. Architecture

Two artifacts:

1. **The mod (this repo)** – Lua scripts that DFHack runs. Steam-Workshop-distributable.
2. **`dfxtwitch.plug.dll`** – future native DFHack plugin (separate repo, GitHub-only). Replaces the external bot by speaking Twitch IRC + Helix directly. Until that ships, the existing external bot can drive the same scripts.

The mod **must work** with either transport. Scripts never assume the plugin is loaded; they fall back to the chat-log file mode when it isn't.

Persistent files used:
- `dfhack-config/DFxTwitch/config.json` – settings (created on first run from `config.example.json`).
- `dfhack-config/DFxTwitch/chatlog.txt` – append-only chat sink for the overlay.
- per-save persistent state (viewer↔dwarf map, religion, leave timers, petition queue, event budget) via DFHack's `persist-table`.

---

## 1. Role ladder

```
Streamer  >  Mod  >  VIP  >  Subscriber  >  Any viewer
```

Higher tiers can run anything below them. Roles come from the bot/plugin in the `--role` arg passed to each script (`streamer | mod | vip | sub | any`). Scripts trust this; bot/plugin enforces.

Cooldowns (per-user unless noted) are configured in `config.json`.

---

## A. Chat commands

| Cmd | Tier | Cooldown | DFHack script | Effect |
|---|---|---|---|---|
| `!join` | any | once / fort / user | `dfxt-claim` | FCFS over unclaimed citizens. If none, replies "Fort full — type `!join migrant` or `!join enemy`". |
| `!join migrant` | any | as above | `dfxt-claim --mode migrant` | Queues viewer for the next *natural* migrant wave. On wave arrival, one new arrival is renamed to viewer. |
| `!join enemy` | mod | as above | `dfxt-claim --mode enemy` | Queues viewer for the next siege/ambush. On arrival, one hostile is renamed to viewer. Hard cap **2 / season**. One-way: name persists in history. |
| `!me` | any | 30s | `dfxt-status --u` | Reply: name, profession, alive/dead, location. |
| `!check <user>` | any | 10s | `dfxt-check --t alive` | One-line alive / dead+cause / wounded. |
| `!skills <user>` | any | 30s | `dfxt-check --t skills` | Top 5 skills. |
| `!skillsfull <user>` | any | 60s | `dfxt-check --t skillsnl` | Full list — DF popup, not chat. |
| `!health <user>` | any | 30s | `dfxt-check --t health` | Short summary. |
| `!healthfull <user>` | any | 60s | `dfxt-check --t healthnl` | DF popup. |
| `!kills <user>` | any | 30s | `dfxt-check --t kills` | Total + 5 of note. |
| `!killsfull <user>` | any | 60s | `dfxt-check --t killsnl` | DF popup. |
| `!relatives <user>` | any | 30s | `dfxt-check --t relatives` | Count of named relations. |
| `!prefs <user>` | any | 30s | `dfxt-check --t preferences` | Likes/detests one-liner. |
| `!prefsfull <user>` | any | 60s | `dfxt-check --t preferencesnl` | DF popup. |
| `!available` | any | 10s global | `dfxt-status --available` | "Miner (3), Mason (2), …" or "none available". |
| `!worship <deity>` | any | 60s | `dfxt-religion --worship` | Set viewer's dwarf worship of an existing deity. Validates deity exists in current world. |
| `!unworship` | any | 60s | `dfxt-religion --unworship` | Drop deity worship. |
| `!religions` | any | 60s global | `dfxt-religion --list` | Bot replies with active entity-religions. |
| `!joinreligion <name>` | VIP | 5min | `dfxt-religion --join` | Join existing entity-religion. |
| `!leavereligion` | any | 5min | `dfxt-religion --leave` | Leave entity-religion. |
| `!leave [days]` | sub | 30min | `dfxt-leave` | Take viewer's dwarf out of squad; auto-rejoin after N (default 28) game days. Survives save/reload. |
| `!squad <name>` | sub | 5min | `dfxt-squad --action join` | Add viewer's dwarf to that squad. |
| `!unsquad` | sub | 10min | `dfxt-squad --action leave` | Leave current squad. |
| `!mods` | any | 5min global | `dfxt-mods` | Active mod list, capped 450 chars. |
| `!ping` | any | 30s | `dfxt-ping` | Health-check + fort name + year + pop. |
| `!commands` | any | 5min global | `dfxt-help` | Posts list of available commands. |

**Streamer-only DFHack console** (not chat-exposed): `dfxt-events fire <name>`, `dfxt-events bucket-c on/off`, `dfxt-events list`, `dfxt-events skip`.

---

## B. Petitions

Trigger conditions:
- Real DF agreements only (Location, Residency, Citizenship, plus a generic-popup fallback for Treaty / Position / Parley / etc.).
- **Polls do NOT fire while** any of: an active siege exists, OR any forgotten/megabeast/titan is alive on the map, OR another chat poll is already open.
- New petitions queue while blocked. As soon as all blockers clear, the next queued poll fires automatically.
- **One open poll at a time, ever.**

Poll mechanics:
- Default duration **90 seconds**, configurable via `config.json: poll_duration_seconds`.
- Choices: `Approve` / `Deny`.
- On `Deny`, plugin auto-clicks Reject in the agreements screen via DFHack GUI simulation. If GUI sim fails (DF version drift), falls back to a popup asking the streamer to click Reject manually. Both paths log to `dfhack-config/DFxTwitch/petitions.log`.
- On `Approve`, no auto-click; the streamer goes to the screen and accepts. (Approve usually requires a building/zone choice anyway.)

Unsupported petition types (Treaty, Position, Parley, etc.) bypass voting — the script pops a DF announcement: *"Petition arrived ({type}) — needs streamer attention."*

---

## C. Events

The mod fires "world events" not tied to in-game petitions. They are gameplay nudges that chat votes on.

Cadence:
- Every **N real-time minutes** (default 15, `event_interval_minutes`). Each tick the scheduler picks at most one event from the eligible buckets.
- Per-bucket fire chance: A 70%, B 30%, C 5%.
- Global cooldown 60s between any two events (prevents back-to-back firing on adjacent ticks).
- Eligibility: Bucket B & C skipped during siege/FB/megabeast. Bucket C also skipped if any citizen has died in the last 5 in-game days.

### Bucket A — Flavor (default ON, no game balance impact)

| Name | Question | Choices | Effect |
|---|---|---|---|
| `weather` | "What weather should hit the fort?" | Rain / Snow / Clear / Good-aligned / Evil-aligned | `changeweather <choice>` (Good/Evil = special precip on supported maps) |
| `cheers` | "Who deserves a toast?" | top 3 popular nicknames | DF announce + mood bump |
| `name_squad` | "Rename {OldSquad} to:" | 3 procedural names | renames the squad |
| `name_fort` | "Suggest a slogan for {fort}:" | chat free response, top-voted | overlay only, no game change |

### Bucket B — Mild nudges (default ON, individually toggleable)

| Name | Question | Choices | Effect |
|---|---|---|---|
| `migrants_race` | "Vote which race comes in the next migrant wave:" | races available in current world | overrides the next migrant wave's race. **Streamer master toggle: `migrants_race_enabled` (default ON).** |
| `caravan` | "Surprise caravan?" | Yes / No | `force Caravan` |
| `bard` | "A bard arrives. Welcome them?" | Welcome / Ignore | flavor announce |

### Bucket C — Real consequences (default OFF, opt-in only via `dfxt-events bucket-c on`)

| Name | Question | Choices | Effect |
|---|---|---|---|
| `ambush` | "Goblin ambush at the gate?" | Yes / No | `force Ambush` |
| `siege_small` | "Send a small siege?" | Yes / No | `force Siege` (small) |
| `forgottenbeast` | "Wake something in the caverns?" | Yes / No | `modtools/create-unit` w/ random FB |
| `floodroom` | "Flood the booze stockpile?" | Yes / No | toggles a magma source if one is built (no-op otherwise) |

Bucket C extra rules:
- Hard cooldown **1 in-game year** between any two C events.
- Max **1 per stream session**.
- Auto-skipped on recent citizen deaths (within 5 in-game days).

### Bucket D
**Not implemented.** Removed by spec. Streamer can still grief their own fort with `dfhack` commands directly if they want.

---

## D. Settings (`dfhack-config/DFxTwitch/config.json`)

```json
{
  "channel": "",
  "bot_username": "",
  "oauth_token": "",
  "client_id": "",

  "poll_duration_seconds": 90,
  "event_interval_minutes": 15,
  "event_global_cooldown_seconds": 60,
  "bucket_a_chance": 0.70,
  "bucket_b_chance": 0.30,
  "bucket_c_chance": 0.05,
  "bucket_c_enabled": false,
  "migrants_race_enabled": true,

  "cooldowns": {
    "default_per_user_seconds": 5,
    "overrides": {}
  },

  "role_aliases": {
    "broadcaster": "streamer",
    "moderator": "mod",
    "vip": "vip",
    "subscriber": "sub"
  },

  "command_map": {
    "!join":          { "script": "dfxt-claim",    "tier": "any" },
    "!me":            { "script": "dfxt-status --u", "tier": "any" },
    "!check":         { "script": "dfxt-check --t alive", "tier": "any" },
    "!skills":        { "script": "dfxt-check --t skills", "tier": "any" },
    "!skillsfull":    { "script": "dfxt-check --t skillsnl", "tier": "any" },
    "!health":        { "script": "dfxt-check --t health", "tier": "any" },
    "!healthfull":    { "script": "dfxt-check --t healthnl", "tier": "any" },
    "!kills":         { "script": "dfxt-check --t kills", "tier": "any" },
    "!killsfull":     { "script": "dfxt-check --t killsnl", "tier": "any" },
    "!relatives":     { "script": "dfxt-check --t relatives", "tier": "any" },
    "!prefs":         { "script": "dfxt-check --t preferences", "tier": "any" },
    "!prefsfull":     { "script": "dfxt-check --t preferencesnl", "tier": "any" },
    "!available":     { "script": "dfxt-status --available", "tier": "any" },
    "!worship":       { "script": "dfxt-religion --worship",   "tier": "any" },
    "!unworship":     { "script": "dfxt-religion --unworship", "tier": "any" },
    "!religions":     { "script": "dfxt-religion --list",      "tier": "any" },
    "!joinreligion":  { "script": "dfxt-religion --join",      "tier": "vip" },
    "!leavereligion": { "script": "dfxt-religion --leave",     "tier": "any" },
    "!leave":         { "script": "dfxt-leave",   "tier": "sub" },
    "!squad":         { "script": "dfxt-squad --action join",  "tier": "sub" },
    "!unsquad":       { "script": "dfxt-squad --action leave", "tier": "sub" },
    "!mods":          { "script": "dfxt-mods",    "tier": "any" },
    "!ping":          { "script": "dfxt-ping",    "tier": "any" },
    "!commands":      { "script": "dfxt-help",    "tier": "any" }
  }
}
```

## E. Persistence (`persist-table` keys, per save)

```
DFxTwitch.viewers.<lower(username)> = {
  unit_id        = <int>,
  hist_fig_id    = <int>,
  joined_year    = <int>,
  status         = "citizen" | "migrant_pending" | "enemy_pending" | "dead",
  death_cause    = <string?>,
  religion       = { deity = <name?>, entity_religion = <name?> },
}

DFxTwitch.leave_queue.<unit_id> = {
  squad_id       = <int>,
  squad_position = <int>,
  rejoin_tick    = <int>,
}

DFxTwitch.petition_queue          = [ <agreement_id>, … ]
DFxTwitch.event_budget = {
  bucket_c_session_used = 0,
  bucket_c_last_year    = 0,
  last_event_tick       = 0,
}
DFxTwitch.poll_state = {
  open      = false,
  type      = "petition" | "event" | nil,
  ref_id    = <any>,
  end_tick  = <int>,
}
```

## F. Acceptance criteria for v1.0-alpha ship

1. `!join` works in three branches (claim / migrant / enemy).
2. All `!check` modes work.
3. Petition queue waits out a siege then resumes.
4. Auto-deny path exists with a working manual fallback.
5. Event scheduler runs and never fires during a blocking condition.
6. `migrants_race` actually changes the next migrant wave's race.
7. Religion commands work for vanilla worlds.
8. All scripts no-op gracefully on bad input (no `qerror` from chat).
9. State survives save/reload.
10. Removing the mod from a save does not crash the save.
