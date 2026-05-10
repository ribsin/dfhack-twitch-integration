// dfxtwitch — Twitch IRC client (raw TCP). Copyright (c) 2025 Ribsin — MIT
//
// Connects to irc.chat.twitch.tv:6667, parses tagged PRIVMSGs, derives a role
// from badges (broadcaster/moderator/vip/subscriber), pushes ChatMessage
// events into the cross-thread queue. Auto-PONG, exponential reconnect.

#include "dfxt.hpp"
#include <atomic>
#include <cstring>
#ifdef _WIN32
  #include <winsock2.h>
  #include <ws2tcpip.h>
  #pragma comment(lib, "Ws2_32.lib")
  using socket_t = SOCKET;
  #define CLOSE closesocket
#else
  #include <sys/socket.h>
  #include <netdb.h>
  #include <unistd.h>
  using socket_t = int;
  static constexpr socket_t INVALID_SOCKET = -1;
  #define CLOSE ::close
#endif

namespace dfxt::irc {

static std::thread        g_thread;
static std::atomic<bool>  g_run{false};
static std::atomic<bool>  g_ready{false};
static std::mutex         g_send_mu;
static socket_t           g_sock = INVALID_SOCKET;
static Config             g_cfg;

static bool ws_init() {
#ifdef _WIN32
    static std::atomic<bool> done{false};
    if (done.exchange(true)) return true;
    WSADATA d; return WSAStartup(MAKEWORD(2,2), &d) == 0;
#else
    return true;
#endif
}

static socket_t connect_tcp(const char* host, const char* port) {
    addrinfo hints{}, *res = nullptr;
    hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(host, port, &hints, &res) != 0) return INVALID_SOCKET;
    socket_t s = INVALID_SOCKET;
    for (auto p = res; p; p = p->ai_next) {
        s = socket(p->ai_family, p->ai_socktype, p->ai_protocol);
        if (s == INVALID_SOCKET) continue;
        if (connect(s, p->ai_addr, (int)p->ai_addrlen) == 0) break;
        CLOSE(s); s = INVALID_SOCKET;
    }
    freeaddrinfo(res);
    return s;
}

static bool send_raw(socket_t s, const std::string& line) {
    auto out = line + "\r\n";
    return ::send(s, out.c_str(), (int)out.size(), 0) == (int)out.size();
}

bool send_chat(const std::string& text) {
    if (!g_ready) return false;
    std::lock_guard<std::mutex> lk(g_send_mu);
    if (g_sock == INVALID_SOCKET) return false;
    return send_raw(g_sock, "PRIVMSG #" + g_cfg.channel + " :" + text.substr(0, 480));
}

// Minimal IRCv3 line parser. Returns tags, prefix, command, params.
struct Line { std::string tags, prefix, cmd; std::vector<std::string> params; };
static Line parse(const std::string& s) {
    Line l; size_t i = 0;
    if (i < s.size() && s[i] == '@') {
        size_t sp = s.find(' ', i);
        l.tags = s.substr(1, sp - 1); i = sp + 1;
    }
    if (i < s.size() && s[i] == ':') {
        size_t sp = s.find(' ', i);
        l.prefix = s.substr(1, sp - 1); i = sp + 1;
    }
    size_t sp = s.find(' ', i);
    l.cmd = s.substr(i, sp - i); i = (sp == std::string::npos) ? s.size() : sp + 1;
    while (i < s.size()) {
        if (s[i] == ':') { l.params.emplace_back(s.substr(i + 1)); break; }
        size_t e = s.find(' ', i);
        if (e == std::string::npos) { l.params.emplace_back(s.substr(i)); break; }
        l.params.emplace_back(s.substr(i, e - i)); i = e + 1;
    }
    return l;
}

static std::string tag(const std::string& tags, const std::string& key) {
    size_t p = tags.find(key + "=");
    if (p == std::string::npos) return {};
    p += key.size() + 1;
    size_t e = tags.find(';', p);
    return tags.substr(p, e == std::string::npos ? std::string::npos : e - p);
}

static std::string role_from_badges(const std::string& badges) {
    if (badges.find("broadcaster/") != std::string::npos) return "streamer";
    if (badges.find("moderator/")   != std::string::npos) return "mod";
    if (badges.find("vip/")         != std::string::npos) return "vip";
    if (badges.find("subscriber/")  != std::string::npos
     || badges.find("founder/")     != std::string::npos) return "sub";
    return "any";
}

static void worker() {
    int backoff = 1;
    while (g_run) {
        socket_t s = connect_tcp("irc.chat.twitch.tv", "6667");
        if (s == INVALID_SOCKET) {
            std::this_thread::sleep_for(std::chrono::seconds(backoff));
            backoff = std::min(backoff * 2, 60);
            continue;
        }
        backoff = 1;
        { std::lock_guard<std::mutex> lk(g_send_mu); g_sock = s; }
        send_raw(s, "CAP REQ :twitch.tv/tags twitch.tv/commands");
        send_raw(s, "PASS oauth:" + g_cfg.oauth_token);
        send_raw(s, "NICK " + (g_cfg.channel.empty() ? std::string("justinfan12345") : g_cfg.channel));
        send_raw(s, "JOIN #" + g_cfg.channel);
        g_ready = true;

        std::string buf; buf.reserve(8192);
        char tmp[4096];
        while (g_run) {
            int n = ::recv(s, tmp, sizeof(tmp), 0);
            if (n <= 0) break;
            buf.append(tmp, n);
            size_t pos;
            while ((pos = buf.find('\n')) != std::string::npos) {
                std::string raw = buf.substr(0, pos);
                buf.erase(0, pos + 1);
                while (!raw.empty() && (raw.back() == '\r' || raw.back() == ' ')) raw.pop_back();
                if (raw.empty()) continue;
                Line l = parse(raw);
                if (l.cmd == "PING") {
                    send_raw(s, "PONG :" + (l.params.empty() ? std::string() : l.params[0]));
                } else if (l.cmd == "PRIVMSG" && l.params.size() >= 2) {
                    evq::Event e;
                    e.kind = evq::Kind::ChatMessage;
                    e.a = tag(l.tags, "display-name");
                    if (e.a.empty()) {
                        auto bang = l.prefix.find('!');
                        e.a = (bang == std::string::npos) ? l.prefix : l.prefix.substr(0, bang);
                    }
                    e.b = role_from_badges(tag(l.tags, "badges"));
                    e.c = l.params[1];
                    evq::push(std::move(e));
                }
            }
        }
        g_ready = false;
        { std::lock_guard<std::mutex> lk(g_send_mu); CLOSE(s); g_sock = INVALID_SOCKET; }
        if (g_run) std::this_thread::sleep_for(std::chrono::seconds(2));
    }
}

bool start(const Config& cfg) {
    if (g_run) return true;
    if (!ws_init()) return false;
    g_cfg = cfg;
    g_run = true;
    g_thread = std::thread(worker);
    return true;
}

void stop() {
    g_run = false;
    {
        std::lock_guard<std::mutex> lk(g_send_mu);
        if (g_sock != INVALID_SOCKET) { CLOSE(g_sock); g_sock = INVALID_SOCKET; }
    }
    if (g_thread.joinable()) g_thread.join();
}

bool connected() { return g_ready; }

} // namespace dfxt::irc
