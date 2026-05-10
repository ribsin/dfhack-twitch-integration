-- dfxt-poll — Twitch native poll wrapper. Copyright (c) 2025 Ribsin — MIT
--
-- Usage from another script:
--   local poll = reqscript('dfxt-poll')
--   poll.open('Approve petition?', {'Approve','Deny'}, 90, function(winner, status)
--       -- winner is the choice TITLE that won, or nil if cancelled/errored
--   end)
--
-- Internals:
--   open() calls tw.poll_create() and stores the poll-id + callback in
--   _G.dfxt_active_poll. The dfxt-overlay heartbeat polls tw.poll_get() every
--   ~5s and, when the poll completes, fires the callback once.
local _ENV = mkmodule('dfxt-poll')

local C = reqscript('dfxt-common')

local function tw()
    local ok, m = pcall(require, 'plugins.dfxtwitch')
    return ok and m or nil
end

local active = nil   -- { id=..., callback=..., started=..., choices=... }

function open(title, choices, duration_s, callback)
    if active then
        if callback then callback(nil, 'BUSY') end
        return false, 'a poll is already open'
    end
    if #choices < 2 or #choices > 5 then
        if callback then callback(nil, 'INVALID') end
        return false, 'need 2..5 choices'
    end
    local m = tw()
    if not m then
        C.say('[poll] plugin not loaded; cannot create Twitch poll.')
        if callback then callback(nil, 'NOPLUGIN') end
        return false, 'no plugin'
    end
    local id, err = m.poll_create(title, choices, duration_s)
    if not id then
        C.say(('[poll] Helix error: %s'):format(tostring(err)))
        if callback then callback(nil, 'ERROR') end
        return false, err
    end
    active = { id = id, callback = callback, choices = choices,
               started = os.time(), last_check = 0 }
    C.say(('[poll] %s — vote on stream now (%ds)'):format(title, duration_s))
    return true
end

-- Called by overlay heartbeat. Polls Helix every 5s while a poll is open.
function tick()
    if not active then return end
    local now = os.time()
    if (now - (active.last_check or 0)) < 5 then return end
    active.last_check = now
    local m = tw()
    if not m then return end
    local p = m.poll_get(active.id)
    if not p.ok then return end
    if p.status == 'ACTIVE' then return end

    -- terminal state — pick the winning choice by votes
    local winner, top = nil, -1
    for _, c in ipairs(p.choices or {}) do
        if (c.votes or 0) > top then top = c.votes; winner = c.title end
    end
    local cb = active.callback
    active = nil
    if cb then pcall(cb, winner, p.status) end
end

function busy() return active ~= nil end

function cancel()
    if not active then return end
    local m = tw()
    if m then pcall(m.poll_cancel, active.id) end
    active = nil
end

return _ENV
