// dfxtwitch — Helix client + WinHTTP HTTPS helper. Copyright (c) 2025 Ribsin — MIT
//
// Windows-only. Uses WinHTTP (ships with every Windows install) instead of
// libcurl. No vcpkg / external HTTPS dependency required.

#include "dfxt.hpp"
#include <nlohmann/json.hpp>

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winhttp.h>

#pragma comment(lib, "winhttp.lib")

using nlohmann::json;
namespace dfxt {

// ---------- http (WinHTTP) ----------
namespace http {

// WinHTTP doesn't need global init/cleanup (per-session handles handle that),
// but we keep the symbols so plugin.cpp doesn't have to change.
void global_init()    {}
void global_cleanup() {}

namespace {

std::wstring widen(const std::string& s) {
    if (s.empty()) return std::wstring();
    int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
    std::wstring w(n, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), w.data(), n);
    return w;
}

std::string narrow(const std::wstring& w) {
    if (w.empty()) return std::string();
    int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), nullptr, 0, nullptr, nullptr);
    std::string s(n, '\0');
    WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), s.data(), n, nullptr, nullptr);
    return s;
}

struct HSession {
    HINTERNET h = nullptr;
    HSession() { h = WinHttpOpen(L"dfxtwitch/1.0",
                                 WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
                                 WINHTTP_NO_PROXY_NAME,
                                 WINHTTP_NO_PROXY_BYPASS, 0); }
    ~HSession() { if (h) WinHttpCloseHandle(h); }
};

struct HConn {
    HINTERNET h = nullptr;
    ~HConn() { if (h) WinHttpCloseHandle(h); }
};

struct HReq {
    HINTERNET h = nullptr;
    ~HReq() { if (h) WinHttpCloseHandle(h); }
};

} // anon

Response request(const std::string& method,
                 const std::string& url,
                 const std::vector<std::string>& headers,
                 const std::string& body)
{
    Response r;

    std::wstring wurl = widen(url);

    URL_COMPONENTS uc{};
    uc.dwStructSize     = sizeof(uc);
    wchar_t host[256] = {0};
    wchar_t path[2048] = {0};
    uc.lpszHostName     = host; uc.dwHostNameLength     = (DWORD)(sizeof(host)/sizeof(wchar_t));
    uc.lpszUrlPath      = path; uc.dwUrlPathLength      = (DWORD)(sizeof(path)/sizeof(wchar_t));
    if (!WinHttpCrackUrl(wurl.c_str(), (DWORD)wurl.size(), 0, &uc)) {
        r.error = "WinHttpCrackUrl failed: " + std::to_string(GetLastError());
        return r;
    }

    HSession sess;
    if (!sess.h) { r.error = "WinHttpOpen failed: " + std::to_string(GetLastError()); return r; }

    HConn conn;
    conn.h = WinHttpConnect(sess.h, host, uc.nPort, 0);
    if (!conn.h) { r.error = "WinHttpConnect failed: " + std::to_string(GetLastError()); return r; }

    DWORD flags = (uc.nScheme == INTERNET_SCHEME_HTTPS) ? WINHTTP_FLAG_SECURE : 0;
    std::wstring wmethod = widen(method);

    HReq req;
    req.h = WinHttpOpenRequest(conn.h, wmethod.c_str(), path,
                               nullptr, WINHTTP_NO_REFERER,
                               WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
    if (!req.h) { r.error = "WinHttpOpenRequest failed: " + std::to_string(GetLastError()); return r; }

    // Compose headers (CRLF-delimited wide string).
    std::wstring hbuf;
    for (auto& h_ : headers) {
        hbuf += widen(h_);
        hbuf += L"\r\n";
    }
    LPCWSTR hptr   = hbuf.empty() ? WINHTTP_NO_ADDITIONAL_HEADERS : hbuf.c_str();
    DWORD   hlen   = hbuf.empty() ? 0 : (DWORD)hbuf.size();

    LPVOID  bptr   = body.empty() ? WINHTTP_NO_REQUEST_DATA : (LPVOID)body.data();
    DWORD   blen   = (DWORD)body.size();

    // 15-second timeouts to match the old libcurl behavior.
    WinHttpSetTimeouts(req.h, 15000, 15000, 15000, 15000);

    if (!WinHttpSendRequest(req.h, hptr, hlen, bptr, blen, blen, 0)) {
        r.error = "WinHttpSendRequest failed: " + std::to_string(GetLastError());
        return r;
    }
    if (!WinHttpReceiveResponse(req.h, nullptr)) {
        r.error = "WinHttpReceiveResponse failed: " + std::to_string(GetLastError());
        return r;
    }

    DWORD status = 0; DWORD slen = sizeof(status);
    WinHttpQueryHeaders(req.h,
                        WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                        WINHTTP_HEADER_NAME_BY_INDEX, &status, &slen,
                        WINHTTP_NO_HEADER_INDEX);
    r.status = (long)status;

    // Drain body.
    for (;;) {
        DWORD avail = 0;
        if (!WinHttpQueryDataAvailable(req.h, &avail)) {
            r.error = "WinHttpQueryDataAvailable failed: " + std::to_string(GetLastError());
            return r;
        }
        if (avail == 0) break;
        std::string chunk(avail, '\0');
        DWORD got = 0;
        if (!WinHttpReadData(req.h, chunk.data(), avail, &got)) {
            r.error = "WinHttpReadData failed: " + std::to_string(GetLastError());
            return r;
        }
        chunk.resize(got);
        r.body += chunk;
        if (got == 0) break;
    }
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
