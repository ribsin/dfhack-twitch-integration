-- dfxt-router — chat → script dispatcher. Copyright (c) 2025 Ribsin — MIT
--
-- Registers a callback with the native plugin via tw.set_message_handler.
-- For every chat line the plugin pushes (user, role, text), we:
--   * trim, lowercase the leading `!command`
--   * look it up in config.command_map
--   * apply role gate + per-user cooldown
--   * shell out to dfxt-* via dfhack.run_command (...) on a fresh thread-safe
--     timer to keep the main thread responsive
local _ENV = mkmodule('dfxt-router')

local C = reqscript('dfxt-common')

local last_seen = {}          -- per-user-per-cmd cooldown timestamps

local function within_cooldown(user, cmd, secs)
    local key = user..':'..cmd
    local now = os.time()
    if (last_seen[key] or 0) + secs > now then return true end
    last_seen[key] = now
    return false
end

-- args.string parser — splits the rest of the message into argv after the !cmd.
local function tokens(rest)
    local out = {}
    for tok in tostring(rest or ''):gmatch('%S+') do out[#out+1] = tok end
    return out
end

local function dispatch(user, role, text)
    local cfg = C.load_config()
    local map = cfg.command_map or {}

    -- find longest-prefix match: e.g. "!join migrant" before "!join"
    local lower = tostring(text):lower():gsub('^%s+', '')
    local cmd, rest
    for k in pairs(map) do
        if lower:sub(1, #k) == k:lower()
           and (#lower == #k or lower:sub(#k+1, #k+1) == ' ') then
            if not cmd or #k > #cmd then
                cmd, rest = k, lower:sub(#k + 2)
            end
        end
    end
    if not cmd then return end

    local entry = map[cmd]
    if not C.role_meets(role, entry.tier or 'any') then
        C.say(('@%s — that command requires %s+.'):format(user, entry.tier))
        return
    end

    local cd = (cfg.cooldowns and cfg.cooldowns.overrides and cfg.cooldowns.overrides[cmd])
            or (cfg.cooldowns and cfg.cooldowns.default_per_user_seconds) or 5
    if within_cooldown(user, cmd, cd) then return end

    -- The "script" string in the map may already carry flags, e.g.
    --   "dfxt-check --t alive"
    local parts = {}
    for w in entry.script:gmatch('%S+') do parts[#parts+1] = w end
    local script_name = table.remove(parts, 1)
    local argv = parts

    -- common args every script understands
    table.insert(argv, '--u');    table.insert(argv, user)
    table.insert(argv, '--role'); table.insert(argv, role)

    -- pass remaining tokens as positional --name / --d / --s where the script
    -- expects them. Per-command argument-shaping happens here.
    local extra = tokens(rest)
    if cmd == '!join' and extra[1] then
        table.insert(argv, '--mode'); table.insert(argv, extra[1])
    elseif cmd == '!check' or cmd == '!skills' or cmd == '!skillsfull'
        or cmd == '!health' or cmd == '!healthfull'
        or cmd == '!kills' or cmd == '!killsfull'
        or cmd == '!relatives' or cmd == '!prefs' or cmd == '!prefsfull' then
        if extra[1] then -- !check <name> — looks up someone else by nickname
            argv[#argv-2] = '--u'  -- already set; replace user with target
            argv[#argv-1] = extra[1]
        end
    elseif cmd == '!worship' or cmd == '!joinreligion' then
        if extra[1] then
            table.insert(argv, '--name'); table.insert(argv, table.concat(extra, ' '))
        end
    elseif cmd == '!squad' then
        if extra[1] then
            table.insert(argv, '--s'); table.insert(argv, table.concat(extra, ' '))
        end
    elseif cmd == '!leave' and tonumber(extra[1]) then
        table.insert(argv, '--d'); table.insert(argv, extra[1])
    end

    -- run on the main thread; dfhack.run_command is synchronous.
    pcall(dfhack.run_command, script_name, table.unpack(argv))
end

function on_message(user, role, text)
    -- never crash on bad input
    pcall(dispatch, user, role or 'any', text or '')
end

function start()
    local ok, tw = pcall(require, 'plugins.dfxtwitch')
    if not ok then
        print('dfxt-router: plugin not loaded; chat dispatch disabled.')
        return false
    end
    tw.set_message_handler(on_message)
    return true
end

return _ENV
