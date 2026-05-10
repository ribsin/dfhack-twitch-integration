// dfxtwitch — Lua bindings. Copyright (c) 2025 Ribsin — MIT
// Exposes `require('plugins.dfxtwitch')` with: connect, disconnect, send_chat,
// poll_create, poll_get, poll_cancel, auth_login, validate_token, status,
// set_message_handler, set_poll_handler.

#include "LuaTools.h"
#include "Core.h"
#include "dfxt.hpp"

#include <map>

using namespace DFHack;

namespace dfxt {

// Stored Lua callback registry refs
static int g_msg_cb_ref = LUA_NOREF;
static int g_poll_cb_ref = LUA_NOREF;

static int l_connect(lua_State* L) {
    Config c;
    if (!load_config(c)) { lua_pushboolean(L, 0); lua_pushstring(L, "config load failed"); return 2; }
    bool ok = irc::start(c);
    lua_pushboolean(L, ok ? 1 : 0);
    return 1;
}

static int l_disconnect(lua_State* L) { irc::stop(); return 0; }

static int l_send_chat(lua_State* L) {
    const char* s = luaL_checkstring(L, 1);
    lua_pushboolean(L, irc::send_chat(s) ? 1 : 0);
    return 1;
}

static int l_validate_token(lua_State* L) {
    Config c; load_config(c);
    auto v = helix::validate(c);
    lua_newtable(L);
    lua_pushboolean(L, v.ok); lua_setfield(L, -2, "ok");
    lua_pushstring(L, v.login.c_str()); lua_setfield(L, -2, "login");
    lua_pushstring(L, v.user_id.c_str()); lua_setfield(L, -2, "user_id");
    lua_pushinteger(L, v.expires_in); lua_setfield(L, -2, "expires_in");
    lua_pushstring(L, v.error.c_str()); lua_setfield(L, -2, "error");
    lua_newtable(L);
    for (size_t i = 0; i < v.scopes.size(); ++i) {
        lua_pushstring(L, v.scopes[i].c_str());
        lua_rawseti(L, -2, (int)i + 1);
    }
    lua_setfield(L, -2, "scopes");
    return 1;
}

static int l_auth_login(lua_State* L) {
    Config c; load_config(c);
    if (c.client_id.empty() || c.client_secret.empty()) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "client_id / client_secret missing in config.json");
        return 2;
    }
    auto r = oauth::login_blocking(c.client_id, c.client_secret,
        { "channel:manage:polls", "channel:read:polls", "chat:read", "chat:edit" });
    if (!r.ok) { lua_pushboolean(L, 0); lua_pushstring(L, r.error.c_str()); return 2; }
    c.oauth_token = r.access_token;
    c.refresh_token = r.refresh_token;
    c.token_expires_at = (int64_t)time(nullptr) + r.expires_in;
    save_config(c);
    lua_pushboolean(L, 1);
    return 1;
}

static int l_poll_create(lua_State* L) {
    const char* title = luaL_checkstring(L, 1);
    luaL_checktype(L, 2, LUA_TTABLE);
    int dur = (int)luaL_checkinteger(L, 3);
    std::vector<std::string> choices;
    int n = (int)lua_rawlen(L, 2);  // Lua 5.3+ rename of lua_objlen
    for (int i = 1; i <= n && i <= 5; ++i) {
        lua_rawgeti(L, 2, i);
        choices.emplace_back(luaL_checkstring(L, -1));
        lua_pop(L, 1);
    }
    Config c; load_config(c);
    auto p = helix::create_poll(c, title, choices, dur);
    if (!p.ok) { lua_pushnil(L); lua_pushstring(L, p.error.c_str()); return 2; }
    lua_pushstring(L, p.id.c_str());
    return 1;
}

static int l_poll_get(lua_State* L) {
    const char* id = luaL_checkstring(L, 1);
    Config c; load_config(c);
    auto p = helix::get_poll(c, id);
    lua_newtable(L);
    lua_pushboolean(L, p.ok); lua_setfield(L, -2, "ok");
    lua_pushstring(L, p.status.c_str()); lua_setfield(L, -2, "status");
    lua_pushstring(L, p.error.c_str()); lua_setfield(L, -2, "error");
    lua_newtable(L);
    for (size_t i = 0; i < p.choices.size(); ++i) {
        lua_newtable(L);
        lua_pushstring(L, p.choices[i].title.c_str()); lua_setfield(L, -2, "title");
        lua_pushinteger(L, p.choices[i].votes);        lua_setfield(L, -2, "votes");
        lua_rawseti(L, -2, (int)i + 1);
    }
    lua_setfield(L, -2, "choices");
    return 1;
}

static int l_poll_cancel(lua_State* L) {
    const char* id = luaL_checkstring(L, 1);
    Config c; load_config(c);
    auto p = helix::end_poll(c, id, /*archive=*/false);
    lua_pushboolean(L, p.ok ? 1 : 0);
    return 1;
}

static int l_set_message_handler(lua_State* L) {
    luaL_checktype(L, 1, LUA_TFUNCTION);
    if (g_msg_cb_ref != LUA_NOREF) luaL_unref(L, LUA_REGISTRYINDEX, g_msg_cb_ref);
    g_msg_cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    return 0;
}
static int l_set_poll_handler(lua_State* L) {
    luaL_checktype(L, 1, LUA_TFUNCTION);
    if (g_poll_cb_ref != LUA_NOREF) luaL_unref(L, LUA_REGISTRYINDEX, g_poll_cb_ref);
    g_poll_cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    return 0;
}

static int l_status(lua_State* L) {
    lua_newtable(L);
    lua_pushboolean(L, irc::connected()); lua_setfield(L, -2, "irc");
    return 1;
}

void register_lua(lua_State* L) {
    static const luaL_Reg fns[] = {
        {"connect",              l_connect},
        {"disconnect",           l_disconnect},
        {"send_chat",            l_send_chat},
        {"validate_token",       l_validate_token},
        {"auth_login",           l_auth_login},
        {"poll_create",          l_poll_create},
        {"poll_get",             l_poll_get},
        {"poll_cancel",          l_poll_cancel},
        {"set_message_handler",  l_set_message_handler},
        {"set_poll_handler",     l_set_poll_handler},
        {"status",               l_status},
        {nullptr, nullptr}
    };
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "loaded");
    lua_newtable(L);
    luaL_setfuncs(L, fns, 0);
    lua_setfield(L, -2, "plugins.dfxtwitch");
    lua_pop(L, 2);
}

// Pump the cross-thread event queue on the main thread.
// `out` is plumbed through from plugin_onupdate so SafeCall has somewhere to
// write Lua errors; the lua_State comes from the main DFHack core. The old
// `Lua::Core::State` namespace variable was removed in DFHack 53.x — the
// canonical way to fetch the core state is `Core::getInstance().getLuaState()`.
void dispatch_pending(color_ostream& out) {
    auto* L = DFHack::Core::getInstance().getLuaState();
    if (!L) return;
    std::vector<evq::Event> batch;
    if (!evq::drain(batch)) return;
    Lua::StackUnwinder top(L);
    for (auto& e : batch) {
        if (e.kind == evq::Kind::ChatMessage && g_msg_cb_ref != LUA_NOREF) {
            lua_rawgeti(L, LUA_REGISTRYINDEX, g_msg_cb_ref);
            lua_pushstring(L, e.a.c_str());   // user
            lua_pushstring(L, e.b.c_str());   // role
            lua_pushstring(L, e.c.c_str());   // text
            Lua::SafeCall(out, L, 3, 0);
        } else if (e.kind == evq::Kind::PollUpdate && g_poll_cb_ref != LUA_NOREF) {
            lua_rawgeti(L, LUA_REGISTRYINDEX, g_poll_cb_ref);
            lua_pushstring(L, e.a.c_str());   // poll_id
            lua_pushstring(L, e.b.c_str());   // status
            lua_pushstring(L, e.c.c_str());   // winner title or ""
            lua_newtable(L);
            for (size_t i = 0; i < e.tally.size(); ++i) {
                lua_newtable(L);
                lua_pushstring(L, e.tally[i].first.c_str()); lua_setfield(L, -2, "title");
                lua_pushinteger(L, e.tally[i].second);       lua_setfield(L, -2, "votes");
                lua_rawseti(L, -2, (int)i + 1);
            }
            Lua::SafeCall(out, L, 4, 0);
        }
    }
}

} // namespace dfxt
