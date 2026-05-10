// dfxtwitch — config.json reader/writer. Copyright (c) 2025 Ribsin — MIT
//
// Reads dfhack-config/DFxTwitch/config.json into a Config struct, and writes
// only the token fields back without clobbering anything else the file holds.
#include "dfxt.hpp"
#include <filesystem>
#include <fstream>
#include <nlohmann/json.hpp>

using nlohmann::json;
namespace dfxt {

std::string config_path() {
    // DFHack runs with DF root as cwd, so a relative path is correct.
    return "dfhack-config/DFxTwitch/config.json";
}

static json read_json_or_empty(const std::string& path) {
    std::ifstream f(path);
    if (!f) return json::object();
    try { return json::parse(f, /*cb=*/nullptr, /*throw=*/false); }
    catch (...) { return json::object(); }
}

bool load_config(Config& out) {
    auto j = read_json_or_empty(config_path());
    if (!j.is_object()) return false;
    out.channel       = j.value("channel", "");
    out.channel_id    = j.value("channel_id", "");
    out.client_id     = j.value("client_id", "");
    out.client_secret = j.value("client_secret", "");
    auto tok = j.value("oauth_token", std::string());
    if (tok.rfind("oauth:", 0) == 0) tok.erase(0, 6);
    out.oauth_token   = tok;
    out.refresh_token = j.value("refresh_token", "");
    out.token_expires_at = j.value("token_expires_at", (int64_t)0);
    return !out.client_id.empty();
}

bool save_config(const Config& cfg) {
    auto j = read_json_or_empty(config_path());
    if (!j.is_object()) j = json::object();
    j["channel"]            = cfg.channel;
    j["channel_id"]         = cfg.channel_id;
    j["client_id"]          = cfg.client_id;
    j["client_secret"]      = cfg.client_secret;
    j["oauth_token"]        = cfg.oauth_token;
    j["refresh_token"]      = cfg.refresh_token;
    j["token_expires_at"]   = cfg.token_expires_at;
    std::error_code ec;
    std::filesystem::create_directories(
        std::filesystem::path(config_path()).parent_path(), ec);
    std::ofstream f(config_path());
    if (!f) return false;
    f << j.dump(2);
    return true;
}

} // namespace dfxt
