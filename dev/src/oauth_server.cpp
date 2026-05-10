// dfxtwitch — OAuth Authorization-Code flow against http://localhost:3000.
// Copyright (c) 2025 Ribsin — MIT
//
// login_blocking() spawns a tiny HTTP listener on the given port, opens the
// system browser at id.twitch.tv/oauth2/authorize, waits for the redirect that
// carries `?code=…`, then exchanges that code for access_token + refresh_token.

#include "dfxt.hpp"
#include <cstdio>
#include <cstdlib>
#include <nlohmann/json.hpp>

#ifdef _WIN32
  #include <winsock2.h>
  #include <ws2tcpip.h>
  #include <windows.h>
  #pragma comment(lib, "Ws2_32.lib")
  using socket_t = SOCKET;
  #define CLOSE closesocket
#else
  #include <sys/socket.h>
  #include <netinet/in.h>
  #include <unistd.h>
  using socket_t = int;
  static constexpr socket_t INVALID_SOCKET = -1;
  #define CLOSE ::close
#endif

using nlohmann::json;
namespace dfxt::oauth {

static std::string url_encode(const std::string& s) {
    static const char* hex = "0123456789ABCDEF";
    std::string o; o.reserve(s.size() * 3);
    for (unsigned char c : s) {
        if (isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') o += (char)c;
        else { o += '%'; o += hex[c >> 4]; o += hex[c & 15]; }
    }
    return o;
}

static void open_browser(const std::string& url) {
#ifdef _WIN32
    ShellExecuteA(nullptr, "open", url.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
#elif __APPLE__
    std::string cmd = "open \"" + url + "\"";
    std::system(cmd.c_str());
#else
    std::string cmd = "xdg-open \"" + url + "\" >/dev/null 2>&1 &";
    std::system(cmd.c_str());
#endif
}

static std::string capture_code(int port) {
#ifdef _WIN32
    WSADATA d; WSAStartup(MAKEWORD(2,2), &d);
#endif
    socket_t srv = ::socket(AF_INET, SOCK_STREAM, 0);
    if (srv == INVALID_SOCKET) return {};
    int yes = 1;
    setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, (const char*)&yes, sizeof(yes));
    sockaddr_in a{}; a.sin_family = AF_INET; a.sin_port = htons((u_short)port);
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (::bind(srv, (sockaddr*)&a, sizeof(a)) < 0) { CLOSE(srv); return {}; }
    if (::listen(srv, 1) < 0) { CLOSE(srv); return {}; }

    socket_t cli = ::accept(srv, nullptr, nullptr);
    CLOSE(srv);
    if (cli == INVALID_SOCKET) return {};
    char buf[4096]; int n = ::recv(cli, buf, sizeof(buf) - 1, 0);
    if (n <= 0) { CLOSE(cli); return {}; }
    buf[n] = 0;
    std::string req(buf);
    std::string code;
    auto p = req.find("code=");
    if (p != std::string::npos) {
        size_t e = req.find_first_of("& \t\r\n", p + 5);
        code = req.substr(p + 5, (e == std::string::npos ? req.size() : e) - (p + 5));
    }
    const char* page =
        "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n"
        "<html><body style='font-family:sans-serif;background:#1a1a1a;color:#eee;text-align:center;padding-top:80px'>"
        "<h1>DFHack Twitch Integration</h1>"
        "<p>Authorization received. You can close this tab and return to Dwarf Fortress.</p>"
        "</body></html>";
    ::send(cli, page, (int)strlen(page), 0);
    CLOSE(cli);
    return code;
}

Result login_blocking(const std::string& client_id,
                      const std::string& client_secret,
                      const std::vector<std::string>& scopes,
                      int port)
{
    Result r;
    std::string scope_str;
    for (size_t i = 0; i < scopes.size(); ++i) {
        if (i) scope_str += ' ';
        scope_str += scopes[i];
    }
    std::string redirect = "http://localhost:" + std::to_string(port);
    std::string url =
        "https://id.twitch.tv/oauth2/authorize"
        "?response_type=code"
        "&client_id=" + url_encode(client_id) +
        "&redirect_uri=" + url_encode(redirect) +
        "&scope=" + url_encode(scope_str) +
        "&force_verify=true";

    open_browser(url);
    std::string code = capture_code(port);
    if (code.empty()) { r.error = "no code received from Twitch"; return r; }

    std::string body =
        "client_id=" + url_encode(client_id) +
        "&client_secret=" + url_encode(client_secret) +
        "&code=" + url_encode(code) +
        "&grant_type=authorization_code" +
        "&redirect_uri=" + url_encode(redirect);

    auto resp = http::request("POST", "https://id.twitch.tv/oauth2/token",
        { "Content-Type: application/x-www-form-urlencoded" }, body);
    if (resp.status / 100 != 2) {
        r.error = "token exchange " + std::to_string(resp.status) + ": " + resp.body;
        return r;
    }
    try {
        auto j = json::parse(resp.body);
        r.access_token  = j.value("access_token", "");
        r.refresh_token = j.value("refresh_token", "");
        r.expires_in    = j.value("expires_in", 0);
        r.ok = !r.access_token.empty();
        if (!r.ok) r.error = "token response missing access_token";
    } catch (std::exception& e) { r.error = e.what(); }
    return r;
}

Result refresh(const std::string& client_id,
               const std::string& client_secret,
               const std::string& refresh_token)
{
    Result r;
    std::string body =
        "grant_type=refresh_token"
        "&refresh_token=" + url_encode(refresh_token) +
        "&client_id=" + url_encode(client_id) +
        "&client_secret=" + url_encode(client_secret);
    auto resp = http::request("POST", "https://id.twitch.tv/oauth2/token",
        { "Content-Type: application/x-www-form-urlencoded" }, body);
    if (resp.status / 100 != 2) {
        r.error = "refresh " + std::to_string(resp.status) + ": " + resp.body;
        return r;
    }
    try {
        auto j = json::parse(resp.body);
        r.access_token  = j.value("access_token", "");
        r.refresh_token = j.value("refresh_token", refresh_token);
        r.expires_in    = j.value("expires_in", 0);
        r.ok = !r.access_token.empty();
    } catch (std::exception& e) { r.error = e.what(); }
    return r;
}

} // namespace dfxt::oauth
