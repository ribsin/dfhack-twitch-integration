-- !ping — health check + fort summary
-- Copyright (c) 2025 Ribsin — MIT
local C = reqscript('dfxt-common')

if not dfhack.world.isFortressMode() or not dfhack.isMapLoaded() then
    C.say('alive — no fort loaded')
    return
end

local fort = '?'
pcall(function()
    fort = dfhack.TranslateName(df.global.world.world_data.active_site[0].name)
end)
local pop = 0
pcall(function()
    pop = #dfhack.units.getCitizens(true)
end)

C.say(('alive — fort %s, year %d, pop %d'):format(fort, df.global.cur_year, pop))
