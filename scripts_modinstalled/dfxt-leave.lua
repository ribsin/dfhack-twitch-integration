-- !leave [days] — temporarily remove a viewer's dwarf from squad with auto-rejoin
-- Copyright (c) 2025 Ribsin — MIT
local C = reqscript('dfxt-common')
local utils = require('utils')
local args = utils.processArgs({...}, utils.invert{'u','role','d','tick'})

local TICKS_PER_DAY = 1200
local user = C.sanitize_username(args.u)
local days = tonumber(args.d) or 28

if args.tick == 'true' then
    -- internal mode: drain the rejoin queue
    local store = C.persist()
    local now = df.global.cur_year_tick
    for uid, q in pairs(store.leave_queue) do
        if q and (q.rejoin_tick or 0) <= now then
            pcall(function()
                local sq = df.squad.find(q.squad_id)
                if sq and sq.positions[q.squad_position] then
                    sq.positions[q.squad_position].occupant = q.hist_fig_id
                end
            end)
            store.leave_queue[uid] = nil
        end
    end
    return
end

if not dfhack.world.isFortressMode() or not dfhack.isMapLoaded() then
    C.say('Fort not loaded.'); return
end
if not user then C.say('Need a user.'); return end
if not C.role_meets(args.role, 'sub') then
    C.say(('@%s — !leave is Sub+.'):format(user)); return
end

local u = (C.find_unit_for_viewer(user))
if not u then C.say(('@%s — not in fort.'):format(user)); return end

-- find their squad slot
local sq_id, slot
for _, sq in ipairs(df.global.world.squads.all) do
    for i, p in ipairs(sq.positions) do
        if p.occupant == u.hist_figure_id then
            sq_id, slot = sq.id, i; break
        end
    end
    if sq_id then break end
end
if not sq_id then
    C.say(('@%s — you are not in a squad.'):format(user)); return
end

local store = C.persist()
store.leave_queue[tostring(u.id)] = {
    squad_id       = sq_id,
    squad_position = slot,
    hist_fig_id    = u.hist_figure_id,
    rejoin_tick    = df.global.cur_year_tick + days * TICKS_PER_DAY,
}
local sq = df.squad.find(sq_id)
if sq then sq.positions[slot].occupant = -1 end
C.say(('@%s — leaving for %d days; will auto-rejoin.'):format(user, days))
