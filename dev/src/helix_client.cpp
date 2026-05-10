// dfxtwitch — Helix client + libcurl HTTPS helper. Copyright (c) 2025 Ribsin — MIT
#include "dfxt.hpp"
#include <curl/curl.h>
#include <nlohmann/json.hpp>

using nlohmann::json;
namespace dfxt {

// ---------- http ----------
namespace http {
void global_init()    { curl_global_init(CURL_GLOBAL_DEFAULT); }
void global_cleanup() { curl_global_cleanup(); }

static size_t write_cb(void* p, size_t s, size_t n, void* ud) {
    ((std::string*)ud)->append((char*)p, s * n); return s * n;
}

Response request(const std::string& method,
                 const std::string& url,
                 const std::vector<std::string>& headers,
                 const std::string& body)
{
    Response r;
    CURL* h = curl_easy_init();
    if (!h) { r.error = "curl_easy_init failed"; return r; }
    curl_slist* hl = nullptr;
    for (auto& h_ : headers) hl = curl_slist_append(hl, h_.c_str());
    curl_easy_setopt(h, CURLOPT_URL, url.c_str());
    curl_easy_setopt(h, CURLOPT_HTTPHEADER, hl);
    curl_easy_setopt(h, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(h, CURLOPT_TIMEOUT, 15L);
    curl_easy_setopt(h, CURLOPT_WRITEFUNCTION, write_cb);
    curl_easy_setopt(h, CURLOPT_WRITEDATA, &r.body);
    if (method == "POST") {
        curl_easy_setopt(h, CURLOPT_POST, 1L);
        curl_easy_setopt(h, CURLOPT_POSTFIELDS, body.c_str());
        curl_easy_setopt(h, CURLOPT_POSTFIELDSIZE, (long)body.size());
    } else if (method == "PATCH" || method == "DELETE") {
        curl_easy_setopt(h, CURLOPT_CUSTOMREQUEST, method.c_str());
        if (!body.empty()) {
            curl_easy_setopt(h, CURLOPT_POSTFIELDS, body.c_str());
            curl_easy_setopt(h, CURLOPT_POSTFIELDSIZE, (long)body.size());
        }
    }
    CURLcode rc = curl_easy_perform(h);
    if (rc != CURLE_OK) r.error = curl_easy_strerror(rc);
    curl_easy_getinfo(h, CURLINFO_RESPONSE_CODE, &r.status);
    curl_slist_free_all(hl);
    curl_easy_cleanup(h);
    return r;
}
} // namespace http

namespace helix {

static std::vector<std::string> auth_headers(const Config& c, bool needs_json) {
    std::vector<std::string> h = {
        "Authorization: Bearer " + c.oauth_token,
        "Client-Id: " + c.client_id,
    };
    if (needs_json) h.emplace_back("Content-Type: application/json");
    return h;
}

ValidateResult validate(const Config& cfg) {
    ValidateResult v;
    if (cfg.oauth_token.empty()) { v.error = "no oauth_token"; return v; }
    auto r = http::request("GET", "https://id.twitch.tv/oauth2/validate",
        { "Authorization: OAuth " + cfg.oauth_token });
    if (r.status != 200) { v.error = r.body.empty() ? r.error : r.body; return v; }
    try {
        auto j = json::parse(r.body);
        v.login      = j.value("login", "");
        v.user_id    = j.value("user_id", "");
        v.expires_in = j.value("expires_in", 0);
        if (j.contains("scopes")) for (auto& s : j["scopes"]) v.scopes.push_back(s.get<std::string>());
        v.ok = true;
    } catch (std::exception& e) { v.error = e.what(); }
    return v;
}

static PollState parse_poll(const json& root) {
    PollState p;
    if (!root.contains("data") || root["data"].empty()) return p;
    auto& d = root["data"][0];
    p.id     = d.value("id", "");
    p.title  = d.value("title", "");
    p.status = d.value("status", "");
    if (d.contains("choices")) {
        for (auto& c : d["choices"]) {
            PollChoice ch;
            ch.id    = c.value("id", "");
            ch.title = c.value("title", "");
            ch.votes = c.value("votes", 0);
            p.choices.emplace_back(std::move(ch));
        }
    }
    p.ok = true;
    return p;
}

PollState create_poll(const Config& cfg, const std::string& title,
                      const std::vector<std::string>& choices, int duration_s)
{
    PollState p;
    if (cfg.channel_id.empty()) { p.error = "channel_id missing — run dfxt-auth"; return p; }
    if (choices.size() < 2 || choices.size() > 5) { p.error = "Twitch polls need 2-5 choices"; return p; }
    if (duration_s < 15) duration_s = 15;
    if (duration_s > 1800) duration_s = 1800;

    json body = {
        {"broadcaster_id", cfg.channel_id},
        {"title", title.substr(0, 60)},
        {"duration", duration_s},
        {"choices", json::array()},
    };
    for (auto& c : choices) body["choices"].push_back({{"title", c.substr(0, 25)}});

    auto r = http::request("POST", "https://api.twitch.tv/helix/polls",
                           auth_headers(cfg, true), body.dump());
    if (r.status / 100 != 2) {
        p.error = "Helix " + std::to_string(r.status) + ": " + r.body;
        return p;
    }
    try { p = parse_poll(json::parse(r.body)); }
    catch (std::exception& e) { p.error = e.what(); }
    return p;
}

PollState get_poll(const Config& cfg, const std::string& id) {
    PollState p;
    auto url = "https://api.twitch.tv/helix/polls?broadcaster_id=" + cfg.channel_id + "&id=" + id;
    auto r = http::request("GET", url, auth_headers(cfg, false));
    if (r.status / 100 != 2) { p.error = "Helix " + std::to_string(r.status) + ": " + r.body; return p; }
    try { p = parse_poll(json::parse(r.body)); }
    catch (std::exception& e) { p.error = e.what(); }
    return p;
}

PollState end_poll(const Config& cfg, const std::string& id, bool archive) {
    PollState p;
    json body = {
        {"broadcaster_id", cfg.channel_id},
        {"id", id},
        {"status", archive ? "ARCHIVED" : "TERMINATED"},
    };
    auto r = http::request("PATCH", "https://api.twitch.tv/helix/polls",
                           auth_headers(cfg, true), body.dump());
    if (r.status / 100 != 2) { p.error = "Helix " + std::to_string(r.status) + ": " + r.body; return p; }
    try { p = parse_poll(json::parse(r.body)); }
    catch (std::exception& e) { p.error = e.what(); }
    return p;
}

} // namespace helix
} // namespace dfxt
