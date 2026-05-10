// dfxtwitch DFHack plugin entry — Copyright (c) 2025 Ribsin — MIT
//
// Registers the `dfxtwitch` plugin with DFHack, owns global lifecycle, and
// pumps the cross-thread event queue once per main-thread tick. The Lua API
// surface lives in lua_api.cpp.

#include "Core.h"
#include "PluginManager.h"
#include "Console.h"
#include "DataDefs.h"
#include "df/world.h"

#include "dfxt.hpp"

using namespace DFHack;

DFHACK_PLUGIN("dfxtwitch");
DFHACK_PLUGIN_IS_ENABLED(g_enabled);

// Forward to lua_api.cpp
namespace dfxt { void register_lua(lua_State* L); void dispatch_pending(); }

DFhackCExport command_result plugin_init(color_ostream& out,
                                         std::vector<PluginCommand>& cmds)
{
    dfxt::http::global_init();
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
    if (g_enabled) dfxt::dispatch_pending();
    return CR_OK;
}

DFhackCExport command_result plugin_enable(color_ostream& out, bool enable)
{
    g_enabled = enable;
    return CR_OK;
}

DFHACK_PLUGIN_LUA_FUNCTIONS {
    DFHACK_LUA_END
};

DFHACK_PLUGIN_LUA_COMMANDS {
    DFHACK_LUA_END
};

// Hook: DFHack calls this when the Lua state is ready.
extern "C" DFhackCExport int plugin_eval_lua(lua_State* L)
{
    dfxt::register_lua(L);
    return 0;
}
