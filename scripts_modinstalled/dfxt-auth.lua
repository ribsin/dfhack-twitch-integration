-- dfxt-auth — Copyright (c) 2025 Ribsin — MIT
-- Streamer-only convenience: opens a browser to the Twitch Authorize page,
-- captures the redirect to http://localhost:3000, exchanges code for tokens,
-- writes them to config.json, and resolves the channel's numeric user-id.

local C = reqscript('dfxt-common')
local ok, tw = pcall(require, 'plugins.dfxtwitch')
if not ok then
    print('dfxtwitch.plug.dll is not loaded — see dev/README.md to build it.')
    return
end

print('Opening Twitch authorization in your browser…')
local ok2, err = tw.auth_login()
if not ok2 then
    print('auth failed: '..tostring(err))
    return
end

print('Tokens stored. Validating…')
local v = tw.validate_token()
if not v.ok then
    print('validate failed: '..tostring(v.error))
    return
end
print(('  login=%s  user_id=%s  expires_in=%ds'):format(
    v.login, v.user_id, v.expires_in))

-- Persist channel + channel_id back into config.json (token_store overwrites
-- those fields on save; we re-load and re-save to capture them here too).
local json = require('json')
local path = 'dfhack-config/DFxTwitch/config.json'
local f = io.open(path, 'r')
local raw = f and f:read('*a') or '{}'
if f then f:close() end
local cfg = (pcall(json.decode, raw)) and json.decode(raw) or {}
cfg.channel    = v.login
cfg.channel_id = v.user_id
f = io.open(path, 'w')
if f then f:write(json.encode(cfg, { indent = true })); f:close() end

print('Done. Run `enable dfxtwitch` then any DF save to start the bot.')
