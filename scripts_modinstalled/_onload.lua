-- Startup hint — Copyright (c) 2025 Ribsin — MIT
-- DFHack auto-runs scripts named _onload.lua from a mod's scripts_modinstalled
-- folder when a save loads. We use it to tell the streamer (and any tail of the
-- DFHack console) what state the mod is in.
local C = reqscript('dfxt-common')

local has_plugin = C.plugin_loaded()
local cfg_exists = (io.open('dfhack-config/DFxTwitch/config.json','r') ~= nil)

print('=== DFHack Twitch Integration v1.0-alpha ===')
if has_plugin then
    print('  native plugin: detected. Run `dfxtwitch start` to connect.')
else
    print('  native plugin: not loaded (use external bot mode).')
end
if not cfg_exists then
    print('  config: dfhack-config/DFxTwitch/config.json missing — copy from config.example.json.')
end
print('  type !commands in chat for the viewer command list.')
