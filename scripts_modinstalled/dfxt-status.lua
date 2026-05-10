-- !me  /  !available — Copyright (c) 2025 Ribsin — MIT
local C = reqscript('dfxt-common')
local utils = require('utils')

local args = utils.processArgs({...}, utils.invert{'u','role','available'})

if not dfhack.world.isFortressMode() or not dfhack.isMapLoaded() then
    C.say('Fort not loaded.')
    return
end

-- ----- !available -----
if args.available then
    local pool = C.unclaimed_citizens()
    if #pool == 0 then
        C.say('none available')
        return
    end
    local counts = {}
    for _, u in ipairs(pool) do
        local p = C.profession_name(u)
        counts[p] = (counts[p] or 0) + 1
    end
    local list = {}
    for n, c in pairs(counts) do list[#list+1] = { n=n, c=c } end
    table.sort(list, function(a,b) return a.c == b.c and a.n < b.n or a.c > b.c end)
    local parts = {}
    for _, e in ipairs(list) do
        parts[#parts+1] = e.c > 1 and ('%s (%d)'):format(e.n, e.c) or e.n
    end
    C.say(table.concat(parts, ', '))
    return
end

-- ----- !me -----
local user = C.sanitize_username(args.u)
if not user then
    C.say('!me needs a username.')
    return
end
local u, rec = C.find_unit_for_viewer(user)
if not rec then
    C.say(('@%s — you have not joined the fort yet. Type !join'):format(user))
    return
end
if rec.status == 'migrant_pending' then
    C.say(('@%s — waiting for the next migrant wave.'):format(user))
    return
end
if rec.status == 'enemy_pending' then
    C.say(('@%s — waiting to spawn with the next siege/ambush.'):format(user))
    return
end
if not u then
    C.say(('@%s — your dwarf is no longer with us.'):format(user))
    return
end
local prof = C.profession_name(u)
local alive = not (u.flags1.dead or u.flags2.killed)
local status = alive and 'alive' or 'dead'
local where = 'somewhere in the fort'
local ok, _ = pcall(function()
    if u.pos and u.pos.z then
        where = ('z=%d'):format(u.pos.z)
    end
end)
C.say(('@%s — %s the %s, %s, %s.'):format(user, user, prof, status, where))
