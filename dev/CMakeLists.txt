# dfxtwitch DFHack plugin — Copyright (c) 2025 Ribsin — MIT
#
# Windows-only. HTTPS via WinHTTP (built into Windows since Vista),
# so no vcpkg / libcurl / OpenSSL dependency.
#
# Two ways to build:
#
#   1. Drop this folder into <dfhack-source>/plugins/dfxtwitch/
#      and add `add_subdirectory(dfxtwitch)` to plugins/CMakeLists.txt
#      — DFHack's standard plugin build picks it up.
#
#   2. Out-of-tree build pointed at a DFHack source checkout via
#      -DDFHACK_SOURCE_DIR=/path/to/dfhack — useful for CI.
#
# Either way the result is `dfxtwitch.plug.dll`,
# to be dropped into <DF>/hack/plugins/.

cmake_minimum_required(VERSION 3.21)

project(dfxtwitch CXX)
# DFHack 53.x headers (MiscUtils.h / BitArray.h / DataDefs.h) use C++20
# concepts (std::invocable, std::assignable_from, std::bidirectional_iterator)
# and the `requires` keyword. C++17 here causes every dfhack include to fail
# with STL4038 + C2039/C2061. See CHANGELOG v1.0-rc9.
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT WIN32)
    message(FATAL_ERROR "dfxtwitch is Windows-only (uses WinHTTP).")
endif()

set(PLUGIN_SRCS
    src/plugin.cpp
    src/lua_api.cpp
    src/irc_client.cpp
    src/helix_client.cpp
    src/oauth_server.cpp
    src/token_store.cpp
    src/event_queue.cpp
)

if(COMMAND DFHACK_PLUGIN)
    # In-tree build (preferred). DFHack provides this macro.
    # `lua` is added to LINK_LIBRARIES so the lua target's INTERFACE include
    # directory propagates — without it, LuaTools.h's `#include "lua.h"` fails
    # because dfhack_plugin() doesn't add the lua include dir transitively in
    # all DFHack revisions.
    DFHACK_PLUGIN(dfxtwitch ${PLUGIN_SRCS} LINK_LIBRARIES winhttp ws2_32 lua)
else()
    # Out-of-tree skeleton: build a shared library named dfxtwitch.plug
    # against a checked-out DFHack tree.
    if(NOT DFHACK_SOURCE_DIR)
        message(FATAL_ERROR
            "Set -DDFHACK_SOURCE_DIR to a checkout of DFHack, "
            "or build this plugin from inside dfhack/plugins/.")
    endif()
    add_library(dfxtwitch SHARED ${PLUGIN_SRCS})
    set_target_properties(dfxtwitch PROPERTIES
        PREFIX ""
        SUFFIX ".plug${CMAKE_SHARED_LIBRARY_SUFFIX}")
    target_include_directories(dfxtwitch PRIVATE
        ${DFHACK_SOURCE_DIR}/library/include
        ${DFHACK_SOURCE_DIR}/library/proto
        ${DFHACK_SOURCE_DIR}/depends/lua/include
    )
    target_link_libraries(dfxtwitch PRIVATE winhttp ws2_32)
endif()

# vendored single-header JSON
target_include_directories(dfxtwitch PRIVATE third_party)
