-- dfxt-doctor — diagnostic. Copyright (c) 2025 Ribsin — MIT
local ok, tw = pcall(require, 'plugins.dfxtwitch')
local function tick(b) return b and '[OK]' or '[--]' end
print('=== DFxTwitch doctor ===')
print(tick(ok)..' dfxtwitch.plug.dll loaded')
if not ok then return end

local cfgf = io.open('dfhack-config/DFxTwitch/config.json','r')
print(tick(cfgf~=nil)..' config.json present')
if cfgf then cfgf:close() end

local v = tw.validate_token()
print(tick(v.ok)..' OAuth token valid '..(v.ok and ('(login='..v.login..', user_id='..v.user_id..')') or ('('..v.error..')')))
local need = { 'channel:manage:polls', 'channel:read:polls', 'chat:read', 'chat:edit' }
local have = {}
for _, s in ipairs(v.scopes or {}) do have[s] = true end
for _, s in ipairs(need) do print(tick(have[s])..' scope '..s) end

local st = tw.status()
print(tick(st.irc)..' IRC connected')

local affiliate = (v.user_id or '') ~= ''
print(tick(affiliate)..' Twitch user resolved (Affiliate/Partner status only checkable by attempting to create a poll)')
