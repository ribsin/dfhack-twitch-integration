-- DFHack Twitch Integration — shared utilities
-- Copyright (c) 2025 Ribsin — MIT
--
-- This module is `reqscript`'d by every other dfxt-* script. It owns:
--   * config loading (dfhack-config/DFxTwitch/config.json)
--   * the role-tier gate
--   * persist-table helpers (see SPEC.md §E)
--   * viewer<->dwarf lookups
--   * a "say to chat" sink that writes a line the bot/plugin can read back
--   * misc small helpers (string sanitize, profession with peasant fallback)
--
-- Nothing here should ever raise a qerror on chat-driven input.

local _ENV = mkmodule('dfxt-common')

local json = require('json')

-- ---------------------------------------------------------------------------
-- paths
-- ---------------------------------------------------------------------------

local CONFIG_DIR  = 'dfhack-config/DFxTwitch'
local CONFIG_PATH = CONFIG_DIR .. '/config.json'
local CHAT_OUT    = CONFIG_DIR .. '/chat-out.txt'   -- we APPEND replies here
local PET_LOG     = CONFIG_DIR .. '/petitions.log'

local DEFAULTS = {
    poll_duration_seconds         = 90,
    event_interval_minutes        = 15,
    event_global_cooldown_seconds = 60,
    bucket_a_chance               = 0.70,
    bucket_b_chance               = 0.30,
    bucket_c_chance               = 0.05,
    bucket_c_enabled              = false,
    migrants_race_enabled         = true,
    cooldowns = { default_per_user_seconds = 5, overrides = {} },
}

-- ---------------------------------------------------------------------------
-- config
-- ---------------------------------------------------------------------------

local _config_cache, _config_mtime

local function ensure_dir()
    local ok = pcall(dfhack.filesystem.mkdir_recursive, CONFIG_DIR)
    return ok
end

local function read_file(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local s = f:read('*a')
    f:close()
    return s
end

function load_config()
    -- mtime-based cache so an edit while DF runs is picked up next call
    local mtime = dfhack.filesystem.mtime(CONFIG_PATH)
    if _config_cache and mtime == _config_mtime then return _config_cache end

    ensure_dir()
    local raw = read_file(CONFIG_PATH)
    local parsed = {}
    if raw then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then parsed = decoded end
    end

    -- shallow-merge defaults
    for k, v in pairs(DEFAULTS) do
        if parsed[k] == nil then parsed[k] = v end
    end
    parsed.cooldowns = parsed.cooldowns or {}
    parsed.cooldowns.default_per_user_seconds =
        parsed.cooldowns.default_per_user_seconds or 5
    parsed.cooldowns.overrides = parsed.cooldowns.overrides or {}

    _config_cache, _config_mtime = parsed, mtime
    return parsed
end

-- ---------------------------------------------------------------------------
-- role gate
-- ---------------------------------------------------------------------------

local TIER_RANK = { any = 0, sub = 1, vip = 2, mod = 3, streamer = 4 }

function role_meets(viewer_role, required_tier)
    local r = TIER_RANK[(viewer_role or 'any'):lower()] or 0
    local t = TIER_RANK[(required_tier or 'any'):lower()] or 0
    return r >= t
end

-- ---------------------------------------------------------------------------
-- persist-table (per save)
-- ---------------------------------------------------------------------------

local function pt()
    return dfhack.persistent.GlobalTable
end

function persist()
    local g = pt()
    g.DFxTwitch = g.DFxTwitch or {}
    g.DFxTwitch.viewers        = g.DFxTwitch.viewers        or {}
    g.DFxTwitch.leave_queue    = g.DFxTwitch.leave_queue    or {}
    g.DFxTwitch.petition_queue = g.DFxTwitch.petition_queue or {}
    g.DFxTwitch.event_budget   = g.DFxTwitch.event_budget   or {
        bucket_c_session_used = 0,
        bucket_c_last_year    = -999,
        last_event_tick       = 0,
    }
    g.DFxTwitch.poll_state = g.DFxTwitch.poll_state or { open = false }
    return g.DFxTwitch
end

-- ---------------------------------------------------------------------------
-- chat output sink — every script that wants to reply does say(text)
-- writes to:
--   1. stdout (so dfhack-run prints it for the external bot to capture)
--   2. dfhack-config/DFxTwitch/chat-out.txt (so the future plugin or any
--      file-watcher bot can pick it up without parsing stdout)
-- ---------------------------------------------------------------------------

function say(text)
    if text == nil or text == '' then return end
    text = tostring(text):gsub('[\r\n]+', ' '):sub(1, 480)
    print(text)
    ensure_dir()
    local f = io.open(CHAT_OUT, 'a')
    if f then
        f:write(text, '\n')
        f:close()
    end
end

function pet_log(line)
    ensure_dir()
    local f = io.open(PET_LOG, 'a')
    if f then
        f:write(os.date('%Y-%m-%d %H:%M:%S '), tostring(line), '\n')
        f:close()
    end
end

-- ---------------------------------------------------------------------------
-- string sanitize for nicknames
-- ---------------------------------------------------------------------------

function sanitize_username(s)
    s = tostring(s or '')
    s = s:gsub('^[%s@#]+', '')
    s = s:gsub('[^%w_%-%.]', '')
    s = s:sub(1, 30)
    if s == '' then return nil end
    return s
end

function lower(s) return tostring(s or ''):lower() end

-- ---------------------------------------------------------------------------
-- viewer <-> unit lookup
-- ---------------------------------------------------------------------------

local function load_unit(unit_id)
    if not unit_id then return nil end
    local u = df.unit.find(unit_id)
    if u and not df.global.world.units.active:_displaced(u) then
        return u
    end
    return u
end

function find_unit_for_viewer(username)
    local key = lower(username)
    local rec = persist().viewers[key]
    if not rec then return nil, nil end
    local u = df.unit.find(rec.unit_id)
    return u, rec
end

function find_unit_by_nickname(name)
    if not name or name == '' then return nil end
    local target = lower(name)
    for _, u in ipairs(df.global.world.units.active) do
        if u and u.name and lower(u.name.nickname) == target then
            return u
        end
    end
    return nil
end

-- get unclaimed citizens (citizens whose nickname is empty)
function unclaimed_citizens()
    local out = {}
    local citizens = dfhack.units.getCitizens(true) -- include children if API supports
    for _, u in ipairs(citizens or {}) do
        if u and u.name and (u.name.nickname == nil or u.name.nickname == '') then
            table.insert(out, u)
        end
    end
    return out
end

function profession_name(unit)
    if not unit then return 'Unknown' end
    local p = dfhack.units.getProfessionName(unit)
    if p == nil or p == '' then p = 'Peasant' end
    return p
end

-- DF-side popup helper (modal info dialog)
function popup(title, body)
    local ok = pcall(function()
        dfhack.gui.showAnnouncement(tostring(title)..': '..tostring(body), COLOR_LIGHTCYAN, true)
    end)
    if not ok then
        print(string.format('[%s] %s', tostring(title), tostring(body)))
    end
end

-- detect the future native plugin
function plugin_loaded()
    local ok = pcall(require, 'plugins.dfxtwitch')
    return ok
end

return _ENV
