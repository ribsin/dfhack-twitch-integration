-- Petition queue + chat polls — Copyright (c) 2025 Ribsin — MIT
-- Subcommands (driven by streamer console or by the bot/plugin tick):
--   dfxt-petitions scan       — pick up new agreements, queue them
--   dfxt-petitions tick       — try to fire next queued poll if no blocker
--   dfxt-petitions resolve --id <agid> --result approve|deny
--   dfxt-petitions list
local C = reqscript('dfxt-common')
local utils = require('utils')
local args = utils.processArgs({...}, utils.invert{'id','result','sub'})
local sub = (args.sub or args[1] or 'scan'):lower()

if not dfhack.world.isFortressMode() or not dfhack.isMapLoaded() then return end

local function siege_or_megabeast_active()
    -- siege flag
    if df.global.plotinfo.siegestate ~= 0 then return 'siege' end
    -- forgotten beast / megabeast units alive on map
    for _, u in ipairs(df.global.world.units.active) do
        if u and not u.flags1.dead and not u.flags2.killed then
            if u.flags2.visitor_uninvited or u.flags1.active_invader then
                return 'invader'
            end
            if u.enemy and u.enemy.undead then return 'undead' end
        end
    end
    return nil
end

local function get_agreements()
    local out = {}
    pcall(function()
        for _, ag in ipairs(df.global.world.agreements.all or {}) do
            if ag and not ag.flags.resolved then
                out[#out+1] = ag
            end
        end
    end)
    return out
end

local function summarize(agreement)
    local txt = 'A petition has arrived.'
    pcall(function()
        if agreement.details then
            txt = ('Petition #%d: type %s'):format(agreement.id,
                tostring(df.agreement_details_type[agreement.details[0]:getType()]))
        end
    end)
    return txt
end

local store = C.persist()
store.petition_queue = store.petition_queue or {}
local seen = store.petitions_seen or {}
store.petitions_seen = seen

-- ----- scan -----
if sub == 'scan' then
    local added = 0
    for _, ag in ipairs(get_agreements()) do
        if not seen[tostring(ag.id)] then
            seen[tostring(ag.id)] = true
            store.petition_queue[#store.petition_queue+1] = ag.id
            added = added + 1
            C.pet_log('queued '..ag.id..' '..summarize(ag))
        end
    end
    if added > 0 then
        C.say(('%d new petition(s) queued. !petitions to start vote.'):format(added))
    end
    return
end

-- ----- list -----
if sub == 'list' then
    if #store.petition_queue == 0 then C.say('No petitions queued.'); return end
    C.say(('%d queued petition(s).'):format(#store.petition_queue))
    return
end

-- ----- tick — try to open the next poll -----
if sub == 'tick' then
    if store.poll_state.open then return end           -- already a poll open
    if #store.petition_queue == 0 then return end
    local block = siege_or_megabeast_active()
    if block then
        C.pet_log('tick blocked: '..block)
        return
    end
    local agid = store.petition_queue[1]
    local ag = df.agreement.find(agid)
    if not ag then
        table.remove(store.petition_queue, 1); return
    end
    local cfg = C.load_config()
    store.poll_state = {
        open      = true,
        type      = 'petition',
        ref_id    = agid,
        end_tick  = df.global.cur_year_tick + (cfg.poll_duration_seconds * 60),
    }
    C.popup('Petition Poll', summarize(ag)..' — chat is voting.')
    C.say(('POLL_OPEN petition #%d duration=%ds — Approve / Deny'):format(
        agid, cfg.poll_duration_seconds))
    return
end

-- ----- resolve — bot/plugin calls back with the chat verdict -----
if sub == 'resolve' then
    local id = tonumber(args.id)
    local res = (args.result or ''):lower()
    if not id or not (res == 'approve' or res == 'deny') then
        C.say('resolve needs --id and --result approve|deny'); return
    end
    if not store.poll_state.open or store.poll_state.ref_id ~= id then
        C.pet_log('resolve mismatch '..tostring(id))
    end
    -- pop from queue
    for i, q in ipairs(store.petition_queue) do
        if q == id then table.remove(store.petition_queue, i); break end
    end
    store.poll_state = { open = false }

    if res == 'deny' then
        local clicked = false
        pcall(function()
            -- Best-effort GUI deny. If structure changes, fall through to popup.
            local view = dfhack.gui.getCurViewscreen(true)
            -- We don't open the agreements screen here automatically;
            -- this is a placeholder that the future plugin will replace
            -- with a robust simulateInput sequence.
            clicked = false
        end)
        if not clicked then
            C.popup('Petition #'..id, 'Chat voted DENY. Please click Reject in the Agreements screen.')
        end
        C.pet_log('resolved '..id..' deny clicked='..tostring(clicked))
        C.say(('Petition #%d — Deny.'):format(id))
    else
        C.popup('Petition #'..id, 'Chat voted APPROVE — please accept on the Agreements screen.')
        C.pet_log('resolved '..id..' approve')
        C.say(('Petition #%d — Approve.'):format(id))
    end
    return
end

C.say('Usage: dfxt-petitions {scan|list|tick|resolve --id N --result approve|deny}')
