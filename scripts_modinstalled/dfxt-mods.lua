-- !mods — list active mods, capped to 450 chars (Twitch headroom).
-- Copyright (c) 2025 Ribsin — MIT
local C = reqscript('dfxt-common')
local utils = require('utils')
local args = utils.processArgs({...}, utils.invert{'role','v'})

local ok, sm = pcall(require, 'script-manager')
if not ok then C.say('mod list unavailable'); return end

local mods = sm.get_active_mods() or {}
local names = {}
for _, m in ipairs(mods) do
    if not m.vanilla or args.v then names[#names+1] = m.name end
end

local MAX = 450
local out, n = '', 0
for _, name in ipairs(names) do
    local sep = (n > 0) and ', ' or ''
    if #out + #sep + #name > MAX then
        out = out .. (' (+%d more)'):format(#names - n)
        break
    end
    out = out .. sep .. name
    n = n + 1
end
if out == '' then out = '(none)' end
C.say(out)
