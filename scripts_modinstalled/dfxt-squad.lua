-- !squad / !unsquad — Copyright (c) 2025 Ribsin — MIT
local C = reqscript('dfxt-common')
local utils = require('utils')
local args = utils.processArgs({...}, utils.invert{'u','role','action','s'})

local user   = C.sanitize_username(args.u)
local action = (args.action or 'join'):lower()
local sname  = args.s

if not dfhack.world.isFortressMode() or not dfhack.isMapLoaded() then
    C.say('Fort not loaded.'); return
end
if not user then C.say('Need a user.'); return end
if not C.role_meets(args.role, 'sub') then
    C.say(('@%s — !squad/!unsquad require Sub+.'):format(user)); return
end

local u = (C.find_unit_for_viewer(user))
if not u then
    C.say(('@%s — you have not joined the fort.'):format(user)); return
end

if action == 'join' then
    if not sname or sname == '' then
        C.say(('@%s — !squad <squadname>'):format(user)); return
    end
    local target_squad
    pcall(function()
        for _, sq in ipairs(df.global.world.squads.all) do
            if C.lower(dfhack.TranslateName(sq.name) or '') == C.lower(sname)
            or C.lower(sq.alias or '') == C.lower(sname) then
                target_squad = sq; break
            end
        end
    end)
    if not target_squad then
        C.say(('@%s — squad "%s" not found.'):format(user, sname)); return
    end
    -- Find a free position in the squad
    local slot
    for i, p in ipairs(target_squad.positions) do
        if p.occupant == -1 then slot = i; break end
    end
    if not slot then
        C.say(('@%s — squad "%s" is full.'):format(user, sname)); return
    end
    target_squad.positions[slot].occupant = u.hist_figure_id or -1
    C.say(('@%s — joined squad "%s".'):format(user, sname))
    return
end

if action == 'leave' then
    local removed
    pcall(function()
        for _, sq in ipairs(df.global.world.squads.all) do
            for _, p in ipairs(sq.positions) do
                if p.occupant == u.hist_figure_id then
                    p.occupant = -1
                    removed = dfhack.TranslateName(sq.name) or sq.alias or '(squad)'
                    return
                end
            end
        end
    end)
    if removed then
        C.say(('@%s — left squad %s.'):format(user, removed))
    else
        C.say(('@%s — you are not in a squad.'):format(user))
    end
    return
end

C.say(('@%s — unknown squad action.'):format(user))
