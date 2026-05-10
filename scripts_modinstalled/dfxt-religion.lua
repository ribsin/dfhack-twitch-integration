-- !worship / !unworship / !religions / !joinreligion / !leavereligion
-- Copyright (c) 2025 Ribsin — MIT
local C = reqscript('dfxt-common')
local utils = require('utils')
local args = utils.processArgs({...}, utils.invert{
    'u','role','worship','unworship','list','join','leave','name'})

if not dfhack.world.isFortressMode() or not dfhack.isMapLoaded() then
    C.say('Fort not loaded.'); return
end

local user = C.sanitize_username(args.u)

local function find_deity(name)
    if not name then return nil end
    local target = C.lower(name)
    for _, hf in ipairs(df.global.world.history.figures) do
        if hf.flags.deity then
            local n = C.lower(dfhack.TranslateName(hf.name) or '')
            if n == target or n:find(target, 1, true) then return hf end
        end
    end
    return nil
end

local function list_entity_religions()
    local rels = {}
    for _, e in ipairs(df.global.world.entities.all) do
        if e.type == df.historical_entity_type.Religion then
            rels[#rels+1] = dfhack.TranslateName(e.name) or '(unnamed)'
        end
    end
    return rels
end

-- ---------- !religions ----------
if args.list then
    local rels = list_entity_religions()
    if #rels == 0 then C.say('No active religions in this world.'); return end
    -- Twitch limit-friendly cap
    local out, n = '', 0
    for _, r in ipairs(rels) do
        local sep = (n > 0) and ', ' or ''
        if #out + #sep + #r > 420 then
            out = out .. (' (+%d more)'):format(#rels - n); break
        end
        out = out .. sep .. r; n = n + 1
    end
    C.say(out)
    return
end

if not user then C.say('Need a user.'); return end
local u, rec = C.find_unit_for_viewer(user)
if not u or not rec then
    C.say(('@%s — join the fort first with !join.'):format(user)); return
end
rec.religion = rec.religion or {}

-- ---------- !worship ----------
if args.worship then
    local deity_name = args.name
    if not deity_name or deity_name == '' then
        C.say(('@%s — !worship <deity name>'):format(user)); return
    end
    local hf = find_deity(deity_name)
    if not hf then
        C.say(('@%s — no deity named "%s" in this world.'):format(user, deity_name))
        return
    end
    rec.religion.deity = dfhack.TranslateName(hf.name)
    -- Note: actually attaching a worship link to the unit's hist fig is
    -- world-version sensitive and is best done by the future plugin via
    -- df.histfig_hf_link_deityst. v1.0-alpha records it in mod state and
    -- announces it; the deity link is left to the plugin.
    C.say(('@%s now worships %s.'):format(user, rec.religion.deity))
    return
end

if args.unworship then
    rec.religion.deity = nil
    C.say(('@%s — no longer worshipping a deity.'):format(user))
    return
end

-- ---------- !joinreligion ----------
if args.join then
    if not C.role_meets(args.role, 'vip') then
        C.say(('@%s — !joinreligion is VIP+.'):format(user)); return
    end
    local rname = args.name
    if not rname then C.say(('@%s — !joinreligion <name>'):format(user)); return end
    local rels = list_entity_religions()
    local match
    for _, r in ipairs(rels) do
        if C.lower(r) == C.lower(rname) then match = r; break end
    end
    if not match then
        C.say(('@%s — no religion named "%s".'):format(user, rname)); return
    end
    rec.religion.entity_religion = match
    C.say(('@%s — joined religion %s.'):format(user, match))
    return
end

if args.leave then
    rec.religion.entity_religion = nil
    C.say(('@%s — left religion.'):format(user))
    return
end

C.say('Unknown religion command.')
