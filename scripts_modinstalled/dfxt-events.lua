-- Event scheduler — Copyright (c) 2025 Ribsin — MIT
-- Subcommands:
--   dfxt-events tick                — scheduler heartbeat (called by overlay)
--   dfxt-events fire <name>         — streamer-only force-fire
--   dfxt-events bucket-c on|off
--   dfxt-events list
--   dfxt-events skip
--   dfxt-events resolve --name N --winner W
local C = reqscript('dfxt-common')
local utils = require('utils')
local args = utils.processArgs({...}, utils.invert{'name','winner','sub'})
local sub  = (args.sub or args[1] or 'tick'):lower()

if not dfhack.world.isFortressMode() or not dfhack.isMapLoaded() then return end

local store = C.persist()
local cfg   = C.load_config()

local function blocked_for_bc()
    -- siege / invader / undead — same predicate as petitions
    local p = reqscript('dfxt-petitions')
    return false  -- petitions module reuses the predicate; events read its result via store
end

local BUCKETS = {
    A = {
        weather    = { q='What weather should hit the fort?',
                        choices={'rain','snow','clear','good','evil'} },
        cheers     = { q='Who deserves a toast?', choices=function()
                        local out={}
                        for _, u in ipairs(dfhack.units.getCitizens(true) or {}) do
                            if u.name.nickname ~= '' and #out < 3 then
                                out[#out+1] = u.name.nickname
                            end
                        end
                        return out
                       end },
        name_squad = { q='Rename next squad?', choices={'Iron','Anvil','Magma'} },
        name_fort  = { q='Slogan for the fort?', choices={} },
    },
    B = {
        migrants_race = { q='Vote race of next migrants:', choices=function()
                            local out, seen = {}, {}
                            for _, c in ipairs(df.global.world.entities.all) do
                                if c.type == df.historical_entity_type.Civilization then
                                    local rid = c.race
                                    if rid >= 0 and not seen[rid] then
                                        seen[rid] = true
                                        local r = df.creature_raw.find(rid)
                                        if r then out[#out+1] = r.creature_id end
                                    end
                                end
                                if #out >= 5 then break end
                            end
                            return out
                          end,
                          gated_by = 'migrants_race_enabled' },
        caravan       = { q='Surprise caravan?', choices={'Yes','No'} },
        bard          = { q='A bard arrives. Welcome them?', choices={'Welcome','Ignore'} },
    },
    C = {
        ambush         = { q='Goblin ambush at the gate?', choices={'Yes','No'} },
        siege_small    = { q='Send a small siege?', choices={'Yes','No'} },
        forgottenbeast = { q='Wake something in the caverns?', choices={'Yes','No'} },
        floodroom      = { q='Flood the booze stockpile?', choices={'Yes','No'} },
    },
}

local function pick_event(bucket)
    local pool = BUCKETS[bucket] or {}
    local keys = {}
    for k, v in pairs(pool) do
        if not v.gated_by or cfg[v.gated_by] ~= false then
            keys[#keys+1] = k
        end
    end
    if #keys == 0 then return nil end
    return keys[math.random(#keys)]
end

local function open_poll(bucket, name)
    local def = BUCKETS[bucket][name]
    if not def then return false end
    local choices = type(def.choices) == 'function' and def.choices() or def.choices
    if not choices then return false end
    -- Twitch native polls need 2-5 choices; pad / cap as required.
    if #choices < 2 then choices[#choices+1] = 'No' end
    while #choices > 5 do table.remove(choices) end
    local cd = cfg.poll_duration_seconds or 90

    local poll = reqscript('dfxt-poll')
    if poll.busy() then return false end

    store.event_budget.last_event_tick = df.global.cur_year_tick
    if bucket == 'C' then
        store.event_budget.bucket_c_session_used =
            (store.event_budget.bucket_c_session_used or 0) + 1
        store.event_budget.bucket_c_last_year = df.global.cur_year
    end
    C.popup('Event Poll', def.q)
    poll.open(def.q, choices, cd, function(winner, status)
        pcall(dfhack.run_command, 'dfxt-events',
              'resolve', '--name', bucket..':'..name,
              '--winner', tostring(winner or '(none)'))
    end)
    return true
end

-- ---------- tick ----------
if sub == 'tick' then
    if store.poll_state.open then return end
    -- global cooldown
    local now = df.global.cur_year_tick
    local cd_ticks = (cfg.event_global_cooldown_seconds or 60) * 60
    if (store.event_budget.last_event_tick or 0) + cd_ticks > now then return end

    local r = math.random()
    local bucket
    if r < (cfg.bucket_a_chance or 0.7) then bucket = 'A'
    elseif r < (cfg.bucket_a_chance + cfg.bucket_b_chance) then bucket = 'B'
    elseif (cfg.bucket_c_enabled) then
        -- bucket C extra rules
        if (df.global.cur_year - (store.event_budget.bucket_c_last_year or -999)) < 1 then
            return  -- 1 in-game year cooldown
        end
        if (store.event_budget.bucket_c_session_used or 0) >= 1 then return end
        bucket = 'C'
    else
        return
    end
    local name = pick_event(bucket)
    if name then open_poll(bucket, name) end
    return
end

-- ---------- fire <name> (streamer only) ----------
if sub == 'fire' then
    local target = (args.name or args[2] or ''):lower()
    if target == '' then C.say('dfxt-events fire <name>'); return end
    for b, pool in pairs(BUCKETS) do
        if pool[target] then open_poll(b, target); return end
    end
    C.say(('Unknown event: %s'):format(target))
    return
end

-- ---------- bucket-c on|off ----------
if sub == 'bucket-c' then
    -- This rewrites config.json to flip the flag.
    cfg.bucket_c_enabled = (args[2] == 'on')
    pcall(dfhack.filesystem.mkdir_recursive, 'dfhack-config/DFxTwitch')
    local f = io.open('dfhack-config/DFxTwitch/config.json', 'r')
    local existing = f and f:read('*a') or '{}'
    if f then f:close() end
    local json = require('json')
    local ok, decoded = pcall(json.decode, existing)
    if not ok or type(decoded) ~= 'table' then decoded = {} end
    decoded.bucket_c_enabled = cfg.bucket_c_enabled
    f = io.open('dfhack-config/DFxTwitch/config.json', 'w')
    if f then f:write(json.encode(decoded, { indent = true })); f:close() end
    C.say(('Bucket C is now %s.'):format(cfg.bucket_c_enabled and 'ON' or 'OFF'))
    return
end

-- ---------- list ----------
if sub == 'list' then
    local out = {}
    for b, pool in pairs(BUCKETS) do
        for n, _ in pairs(pool) do out[#out+1] = b..':'..n end
    end
    table.sort(out)
    print(table.concat(out, '\n'))
    return
end

-- ---------- skip ----------
if sub == 'skip' then
    if store.poll_state.open then store.poll_state = { open = false } end
    C.say('Skipped any open event poll.')
    return
end

-- ---------- resolve ----------
if sub == 'resolve' then
    local name   = args.name or ''
    local winner = args.winner or ''
    if not store.poll_state.open then return end
    store.poll_state = { open = false }
    -- The actual side-effects per event live in subhandlers; we just
    -- announce + log here for v1.0-alpha. A future iteration / plugin
    -- will call into specific handlers.
    C.popup('Event '..name, 'Winner: '..winner)
    C.say(('Event %s — winner: %s'):format(name, winner))
    return
end

C.say('dfxt-events {tick|fire <name>|bucket-c on|off|list|skip|resolve --name N --winner W}')
