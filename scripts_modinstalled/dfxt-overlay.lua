-- DF-side chat overlay + scheduler heartbeat — Copyright (c) 2025 Ribsin — MIT
--
-- Renders the last N chat lines on the dwarfmode screen and uses its 1-Hz
-- redraw tick to drive every piece of background work the mod has:
--
--   * dfxt-poll.tick()                  poll Helix every 5 s while a poll is open
--   * dfxt-leave  --tick true           auto-rejoin squad members
--   * dfxt-petitions scan + tick        queue / resolve petitions
--   * dfxt-events tick                  events scheduler (configurable interval)
--
-- The chat-line buffer is filled by dfxt-router from messages the native
-- plugin pushes via tw.set_message_handler — no file tail any more.

local overlay = require('plugins.overlay')
local C       = reqscript('dfxt-common')
local poll    = reqscript('dfxt-poll')

-- ring buffer dfxt-router writes to. Exposed on the global `dfxt_chat_lines`
-- so the router doesn't have to import the overlay module.
_G.dfxt_chat_lines = _G.dfxt_chat_lines or {}
local TAIL_LINES = 8

function dfxt_push_chat_line(s)
    table.insert(_G.dfxt_chat_lines, tostring(s):sub(1, 60))
    while #_G.dfxt_chat_lines > TAIL_LINES do
        table.remove(_G.dfxt_chat_lines, 1)
    end
end

ChatOverlay = defclass(ChatOverlay, overlay.OverlayWidget)
ChatOverlay.ATTRS{
    default_pos = { x = 2, y = -10 },
    default_enabled = true,
    viewscreens = { 'dwarfmode' },
    frame = { w = 62, h = TAIL_LINES + 1 },
    overlay_onupdate_max_freq_seconds = 1,
}

local _heartbeat_counter = 0
local _last_event_check  = 0

function ChatOverlay:onUpdate()
    -- 5-second poll-check cadence is enforced inside dfxt-poll itself.
    pcall(poll.tick)

    _heartbeat_counter = _heartbeat_counter + 1
    if _heartbeat_counter < 60 then return end       -- ~60-s slow ticks
    _heartbeat_counter = 0

    pcall(dfhack.run_command, 'dfxt-leave', '--tick', 'true')
    pcall(dfhack.run_command, 'dfxt-petitions', 'scan')
    pcall(dfhack.run_command, 'dfxt-petitions', 'tick')

    local cfg = C.load_config()
    local interval = (cfg.event_interval_minutes or 15) * 60
    if (os.time() - _last_event_check) >= interval then
        _last_event_check = os.time()
        pcall(dfhack.run_command, 'dfxt-events', 'tick')
    end
end

function ChatOverlay:onRenderBody(dc)
    local lines = _G.dfxt_chat_lines or {}
    if #lines == 0 then return end
    for i, l in ipairs(lines) do
        dc:seek(0, i - 1):string(l)
    end
end

OVERLAY_WIDGETS = { chat = ChatOverlay }
