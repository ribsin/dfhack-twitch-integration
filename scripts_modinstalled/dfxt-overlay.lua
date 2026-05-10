-- DF-side chat overlay + scheduler heartbeat — Copyright (c) 2025 Ribsin — MIT
--
-- Reads dfhack-config/DFxTwitch/chatlog.txt (written by the bot or future
-- plugin), shows the last N lines on the dwarfmode screen, and uses the
-- redraw tick to drive periodic background work:
--   * dfxt-leave --tick true             (auto-rejoin squad members)
--   * dfxt-petitions scan + tick         (queue polls)
--   * dfxt-events tick                   (events scheduler)

local overlay = require('plugins.overlay')
local C = reqscript('dfxt-common')

local CHATLOG = 'dfhack-config/DFxTwitch/chatlog.txt'
local TAIL_LINES = 8
local last_offset = 0
local lines = {}

local function read_tail()
    local f = io.open(CHATLOG, 'rb')
    if not f then return end
    local sz = f:seek('end')
    if sz < last_offset then last_offset = 0 end -- log was rotated
    if sz <= last_offset then f:close(); return end
    f:seek('set', last_offset)
    local chunk = f:read('*a') or ''
    last_offset = sz
    f:close()
    for line in chunk:gmatch('[^\n]+') do
        lines[#lines+1] = line
        while #lines > TAIL_LINES do table.remove(lines, 1) end
    end
end

ChatOverlay = defclass(ChatOverlay, overlay.OverlayWidget)
ChatOverlay.ATTRS{
    default_pos = { x = 2, y = -10 },
    default_enabled = true,
    viewscreens = { 'dwarfmode' },
    frame = { w = 60, h = TAIL_LINES + 1 },
    overlay_onupdate_max_freq_seconds = 1,
}

local _heartbeat_counter = 0

function ChatOverlay:onUpdate()
    pcall(read_tail)
    -- heartbeat: roughly every (event_interval_minutes) minutes
    _heartbeat_counter = _heartbeat_counter + 1
    if _heartbeat_counter >= 60 then     -- ~60s ticks
        _heartbeat_counter = 0
        pcall(dfhack.run_command, 'dfxt-leave', '--tick', 'true')
        pcall(dfhack.run_command, 'dfxt-petitions', 'scan')
        pcall(dfhack.run_command, 'dfxt-petitions', 'tick')
        local cfg = C.load_config()
        local interval = (cfg.event_interval_minutes or 15) * 60
        if (os.time() - (self._last_event_check or 0)) >= interval then
            self._last_event_check = os.time()
            pcall(dfhack.run_command, 'dfxt-events', 'tick')
        end
    end
end

function ChatOverlay:onRenderBody(dc)
    if #lines == 0 then return end
    for i, l in ipairs(lines) do
        dc:seek(0, i-1):string(l:sub(1, 60))
    end
end

OVERLAY_WIDGETS = { chat = ChatOverlay }
