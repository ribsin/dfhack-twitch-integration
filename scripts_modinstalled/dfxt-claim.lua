-- !join — Copyright (c) 2025 Ribsin — MIT
-- Modes:
--   (default) FCFS over unclaimed citizens; if none -> reply with options
--   --mode migrant : queue viewer for next natural migrant wave
--   --mode enemy   : queue viewer for next siege/ambush (mod tier required)
local C = reqscript('dfxt-common')
local utils = require('utils')

local args = utils.processArgs({...}, utils.invert{'u','role','mode'})
local user = C.sanitize_username(args.u)
local role = (args.role or 'any'):lower()
local mode = (args.mode or 'fcfs'):lower()

if not dfhack.world.isFortressMode() or not dfhack.isMapLoaded() then
    C.say('Fort not loaded.')
    return
end
if not user then
    C.say('!join needs a username.')
    return
end

local store = C.persist()
local key   = C.lower(user)

-- already-claimed?
if store.viewers[key] then
    local rec = store.viewers[key]
    local u = df.unit.find(rec.unit_id)
    if u and rec.status == 'citizen' then
        C.say(('@%s already plays %s the %s.'):format(user, user, C.profession_name(u)))
        return
    elseif rec.status == 'migrant_pending' then
        C.say(('@%s already queued for the next migrant wave.'):format(user))
        return
    elseif rec.status == 'enemy_pending' then
        C.say(('@%s already queued to spawn as an enemy.'):format(user))
        return
    end
    -- stale (dead etc.) — fall through, let them rejoin
end

-- ---------- mode: migrant ----------
if mode == 'migrant' then
    store.viewers[key] = {
        unit_id     = -1,
        joined_year = df.global.cur_year,
        status      = 'migrant_pending',
    }
    C.say(('@%s — you will arrive with the next migrant wave.'):format(user))
    return
end

-- ---------- mode: enemy ----------
if mode == 'enemy' then
    if not C.role_meets(role, 'mod') then
        C.say(('@%s — !join enemy is mod-only (no chaos democracy).'):format(user))
        return
    end
    -- season cap of 2
    local season = df.global.cur_season + (df.global.cur_year * 4)
    store.enemy_season  = store.enemy_season  or season
    store.enemy_used    = store.enemy_used    or 0
    if store.enemy_season ~= season then
        store.enemy_season, store.enemy_used = season, 0
    end
    if store.enemy_used >= 2 then
        C.say(('@%s — enemy slots full this season; try later.'):format(user))
        return
    end
    store.enemy_used = store.enemy_used + 1
    store.viewers[key] = {
        unit_id     = -1,
        joined_year = df.global.cur_year,
        status      = 'enemy_pending',
    }
    C.say(('@%s — you will arrive with the next siege/ambush. (No takebacks.)'):format(user))
    return
end

-- ---------- mode: fcfs (default) ----------
local pool = C.unclaimed_citizens()
if #pool == 0 then
    C.say(('@%s — fort is full. Reply !join migrant or (mods) !join enemy.'):format(user))
    return
end

local pick = pool[math.random(#pool)]
pick.name.nickname = user
pick.name.has_name = true
local hf = pick.hist_figure_id and df.historical_figure.find(pick.hist_figure_id)
if hf and hf.name then hf.name.nickname = user end

store.viewers[key] = {
    unit_id     = pick.id,
    hist_fig_id = pick.hist_figure_id,
    joined_year = df.global.cur_year,
    status      = 'citizen',
}
C.say(('@%s now plays %s the %s.'):format(user, user, C.profession_name(pick)))
