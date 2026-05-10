-- Startup — Copyright (c) 2025 Ribsin — MIT
-- DFHack auto-runs _onload.lua from a mod's scripts_modinstalled folder when
-- a save loads. We use it to: load config, connect IRC via the plugin,
-- register the chat router, and announce mod state on the console.

local C = reqscript('dfxt-common')

print('=== DFHack Twitch Integration v1.0 ===')

local cfg_exists = (io.open('dfhack-config/DFxTwitch/config.json','r') ~= nil)
if not cfg_exists then
    print('  config missing: copy config.example.json -> dfhack-config/DFxTwitch/config.json,')
    print('  fill in client_id + client_secret, then run: dfxt-auth')
    return
end

local ok, tw = pcall(require, 'plugins.dfxtwitch')
if not ok then
    print('  plugin dfxtwitch.plug.dll NOT loaded.')
    print('  Build it from dev/ — see dev/README.md.  Mod will not function until it is installed.')
    return
end

-- Connect (non-blocking; the plugin's IRC worker handles reconnects).
local connected = tw.connect()
print(('  plugin: loaded, irc.connect=%s'):format(tostring(connected)))

-- Hook chat → script dispatcher.
local router = reqscript('dfxt-router')
router.start()

-- Validate token freshness (informational only).
local v = tw.validate_token()
if v.ok then
    print(('  token: %s (user_id=%s, %ds remaining)'):format(v.login, v.user_id, v.expires_in or 0))
else
    print('  token: INVALID — run dfxt-auth.  ('..tostring(v.error)..')')
end

-- Hand off to the overlay heartbeat for ongoing ticks (events, polls, leaves).
dfhack.run_command('dfxt-overlay', 'start')
print('  type !commands in Twitch chat for the viewer command list.')
