# dfxtwitch DFHack plugin — Copyright (c) 2025 Ribsin — MIT
#
# This CMakeLists.txt is intended to be used in two ways:
#
#   1. Drop this folder into <dfhack-source>/plugins/dfxtwitch/
#      and add `add_subdirectory(dfxtwitch)` to plugins/CMakeLists.txt
#      — DFHack's standard plugin build picks it up.
#
#   2. Out-of-tree build pointed at a DFHack source checkout via
#      -DDFHACK_SOURCE_DIR=/path/to/dfhack — useful for CI.
#
# Either way the result is `dfxtwitch.plug.dll` (Windows) or
# `dfxtwitch.plug.so` (Linux), to be dropped into <DF>/hack/plugins/.

cmake_minimum_required(VERSION 3.21)

project(dfxtwitch CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

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
    DFHACK_PLUGIN(dfxtwitch ${PLUGIN_SRCS} LINK_LIBRARIES CURL::libcurl)
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
    find_package(CURL REQUIRED)
    target_link_libraries(dfxtwitch PRIVATE CURL::libcurl)
endif()

# vendored single-header JSON
target_include_directories(dfxtwitch PRIVATE third_party)
