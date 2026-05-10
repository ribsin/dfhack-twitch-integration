// dfxtwitch DFHack plugin entry — Copyright (c) 2025 Ribsin — MIT
//
// Registers the `dfxtwitch` plugin with DFHack, owns global lifecycle, and
// pumps the cross-thread event queue once per main-thread tick. The Lua API
// surface lives in lua_api.cpp.

#include "Core.h"
#include "PluginManager.h"
#include "PluginLua.h"        // DFHACK_PLUGIN_LUA_FUNCTIONS / _COMMANDS / DFHACK_LUA_END
#include "Console.h"
#include "DataDefs.h"
#include "df/world.h"

#include "dfxt.hpp"

using namespace DFHack;

DFHACK_PLUGIN("dfxtwitch");
DFHACK_PLUGIN_IS_ENABLED(g_enabled);

// Forward to lua_api.cpp.
// dispatch_pending takes a color_ostream so Lua::SafeCall has somewhere to
// write Lua errors — see lua_api.cpp comment for why we don't use a global.
namespace dfxt {
    void register_lua(lua_State* L);
    void dispatch_pending(color_ostream& out);
}

DFhackCExport command_result plugin_init(color_ostream& out,
                                         std::vector<PluginCommand>& cmds)
{
    dfxt::http::global_init();
    // Register `package.loaded["plugins.dfxtwitch"]` against the DFHack core
    // Lua state so `require('plugins.dfxtwitch')` from any DFHack script
    // returns our function table. We do this manually because our Lua
    // bindings take raw lua_State* (luaL_Reg style) rather than the
    // df::wrap_function style that DFHACK_PLUGIN_LUA_FUNCTIONS expects.
    if (auto* L = Core::getInstance().getLuaState())
        dfxt::register_lua(L);
    return CR_OK;
}

DFhackCExport command_result plugin_shutdown(color_ostream& out)
{
    dfxt::irc::stop();
    dfxt::http::global_cleanup();
    return CR_OK;
}

DFhackCExport command_result plugin_onupdate(color_ostream& out)
{
    if (g_enabled) dfxt::dispatch_pending(out);
    return CR_OK;
}

DFhackCExport command_result plugin_enable(color_ostream& out, bool enable)
{
    g_enabled = enable;
    return CR_OK;
}

// Empty arrays — we register Lua functions manually in plugin_init (see
// above). DFHack still inspects these symbols to decide whether to surface
// a `plugins.<name>` Lua module via the wrapper machinery, so leaving them
// defined-and-empty is the safe default.
DFHACK_PLUGIN_LUA_FUNCTIONS {
    DFHACK_LUA_END
};

DFHACK_PLUGIN_LUA_COMMANDS {
    DFHACK_LUA_END
};
