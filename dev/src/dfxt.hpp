// dfxtwitch — internal header. Copyright (c) 2025 Ribsin — MIT
#pragma once
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <functional>
#include <memory>
#include <mutex>
#include <queue>
#include <string>
#include <thread>
#include <vector>

namespace dfxt {

struct Config {
    std::string channel;
    std::string channel_id;          // numeric Twitch user-id, fetched at validate()
    std::string client_id;
    std::string client_secret;
    std::string oauth_token;         // current access_token (no "oauth:" prefix)
    std::string refresh_token;
    int64_t     token_expires_at = 0; // epoch seconds
};

bool   load_config(Config& out);
bool   save_config(const Config& cfg);   // updates only token fields, preserves other keys
std::string config_path();

// ----- IRC -----
namespace irc {
bool start(const Config& cfg);
void stop();
bool connected();
bool send_chat(const std::string& text);
struct Message { std::string user, role, text; };
}

// ----- Helix -----
namespace helix {
struct ValidateResult {
    bool ok = false;
    std::string login, user_id;
    std::vector<std::string> scopes;
    int expires_in = 0;
    std::string error;
};
ValidateResult validate(const Config& cfg);

struct PollChoice { std::string id; std::string title; int votes = 0; };
struct PollState  {
    bool ok = false;
    std::string id;
    std::string status;              // ACTIVE | COMPLETED | TERMINATED | ARCHIVED | MODERATED | INVALID
    std::string title;
    std::vector<PollChoice> choices;
    std::string error;
};
PollState create_poll(const Config& cfg, const std::string& title,
                      const std::vector<std::string>& choices, int duration_s);
PollState get_poll(const Config& cfg, const std::string& poll_id);
PollState end_poll(const Config& cfg, const std::string& poll_id, bool archive);
}

// ----- OAuth (localhost:3000 code grab + token exchange) -----
namespace oauth {
struct Result {
    bool ok = false;
    std::string access_token, refresh_token;
    int expires_in = 0;
    std::string error;
};
Result login_blocking(const std::string& client_id,
                      const std::string& client_secret,
                      const std::vector<std::string>& scopes,
                      int port = 3000);
Result refresh(const std::string& client_id,
               const std::string& client_secret,
               const std::string& refresh_token);
}

// ----- Cross-thread event queue (worker → main) -----
namespace evq {
enum class Kind { ChatMessage, PollUpdate, Status };
struct Event {
    Kind kind;
    std::string a, b, c;             // generic string slots
    std::vector<std::pair<std::string,int>> tally; // for PollUpdate
};
void push(Event e);
bool drain(std::vector<Event>& out, size_t max = 64);
}

// ----- libcurl HTTPS helper used by helix + oauth -----
namespace http {
struct Response { long status = 0; std::string body, error; };
Response request(const std::string& method,
                 const std::string& url,
                 const std::vector<std::string>& headers,
                 const std::string& body = std::string());
void global_init();
void global_cleanup();
}

} // namespace dfxt
