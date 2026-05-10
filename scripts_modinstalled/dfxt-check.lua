-- !check / !skills(full) / !health(full) / !kills(full) / !relatives / !prefs(full)
-- Copyright (c) 2025 Ribsin — MIT
local C = reqscript('dfxt-common')
local utils = require('utils')

local args = utils.processArgs({...}, utils.invert{'u','t','role'})
local user = C.sanitize_username(args.u)
local kind = (args.t or 'alive'):lower()

if not dfhack.world.isFortressMode() or not dfhack.isMapLoaded() then
    C.say('Fort not loaded.')
    return
end
if not user then
    C.say('Usage: !check <username>')
    return
end

-- locate target: nickname match (any unit), then viewer table
local u = C.find_unit_by_nickname(user)
if not u then u = (C.find_unit_for_viewer(user)) end
if not u then
    C.say(('No dwarf named %s.'):format(user))
    return
end

local hf = u.hist_figure_id and df.historical_figure.find(u.hist_figure_id) or nil

-- ---------- alive ----------
if kind == 'alive' then
    if u.flags1.dead or u.flags2.killed then
        local cause = 'unknown causes'
        if hf and hf.died_year and hf.died_year > 0 then
            cause = ('died %d.%d'):format(hf.died_year, hf.died_seconds or 0)
        end
        C.say(('%s is dead (%s).'):format(user, cause))
        return
    end
    -- crude wound check
    local hurt = false
    pcall(function()
        for _, w in ipairs(u.body.wounds) do
            if w then hurt = true; break end
        end
    end)
    C.say(('%s is %s.'):format(user, hurt and 'wounded but alive' or 'alive and well'))
    return
end

-- ---------- skills ----------
if kind == 'skills' or kind == 'skillsnl' then
    local skills = {}
    pcall(function()
        local soul = u.status.current_soul
        if not soul then return end
        for _, s in ipairs(soul.skills) do
            if s and s.rating and s.rating > 0 then
                skills[#skills+1] = {
                    name = df.job_skill[s.id] or ('skill#'..tostring(s.id)),
                    rating = s.rating,
                }
            end
        end
    end)
    table.sort(skills, function(a,b) return a.rating > b.rating end)
    if #skills == 0 then
        C.say(('%s has no notable skills.'):format(user))
        return
    end
    if kind == 'skillsnl' then
        local lines = {}
        for _, s in ipairs(skills) do
            lines[#lines+1] = ('  %s — lvl %d'):format(s.name, s.rating)
        end
        C.popup(user..' skills', '\n'..table.concat(lines, '\n'))
        C.say(('%s skills shown on stream.'):format(user))
    else
        local top = {}
        for i = 1, math.min(5, #skills) do
            top[#top+1] = ('%s %d'):format(skills[i].name, skills[i].rating)
        end
        C.say(('%s top skills: %s.'):format(user, table.concat(top, ', ')))
    end
    return
end

-- ---------- health ----------
if kind == 'health' or kind == 'healthnl' then
    local fine = not (u.flags1.dead or u.flags2.killed)
    local notes = {}
    pcall(function()
        if u.body.blood_count < u.body.blood_max then
            notes[#notes+1] = ('blood %d%%'):format(math.floor(100 * u.body.blood_count / math.max(1,u.body.blood_max)))
        end
        for _, w in ipairs(u.body.wounds) do
            if w then notes[#notes+1] = 'wounded'; break end
        end
    end)
    if kind == 'healthnl' then
        C.popup(user..' health', table.concat(notes, ', ') ~= '' and table.concat(notes, ', ') or 'no notable issues')
        C.say(('%s health shown on stream.'):format(user))
    else
        if not fine then
            C.say(('%s — DECEASED.'):format(user))
        elseif #notes == 0 then
            C.say(('%s — fit and well.'):format(user))
        else
            C.say(('%s — %s.'):format(user, table.concat(notes, ', ')))
        end
    end
    return
end

-- ---------- kills ----------
if kind == 'kills' or kind == 'killsnl' then
    if not hf then C.say(('%s has no recorded history.'):format(user)); return end
    local total, of_note = 0, {}
    pcall(function()
        for _, k in ipairs(hf.kills.killed_undead) do total = total + 1 end
        for _, ev in ipairs(hf.kills.events or {}) do total = total + 1 end
    end)
    if kind == 'killsnl' then
        C.popup(user..' kills', ('Total kill events: %d'):format(total))
        C.say(('%s — %d kills (full list on stream).'):format(user, total))
    else
        C.say(('%s — %d kills total.'):format(user, total))
    end
    return
end

-- ---------- relatives ----------
if kind == 'relatives' or kind == 'relativesnl' then
    local count = 0
    pcall(function()
        if hf and hf.histfig_links then
            for _, l in ipairs(hf.histfig_links) do
                if l._type == df.histfig_hf_link_spousest
                or l._type == df.histfig_hf_link_childst
                or l._type == df.histfig_hf_link_motherst
                or l._type == df.histfig_hf_link_fatherst then
                    count = count + 1
                end
            end
        end
    end)
    C.say(('%s has %d named relatives in the historical record.'):format(user, count))
    return
end

-- ---------- preferences ----------
if kind == 'preferences' or kind == 'preferencesnl' then
    local likes, n = {}, 0
    pcall(function()
        local soul = u.status.current_soul
        if not soul then return end
        for _, p in ipairs(soul.preferences) do
            n = n + 1
            if #likes < 5 then likes[#likes+1] = ('pref#'..tostring(p.type)) end
        end
    end)
    if kind == 'preferencesnl' then
        C.popup(user..' preferences', ('%d preferences'):format(n))
        C.say(('%s preferences on stream.'):format(user))
    else
        C.say(('%s has %d preferences.'):format(user, n))
    end
    return
end

C.say(('Unknown check type: %s'):format(kind))
