// dfxtwitch — cross-thread event queue. Copyright (c) 2025 Ribsin — MIT
#include "dfxt.hpp"
namespace dfxt::evq {
static std::mutex          g_mu;
static std::deque<Event>   g_q;

void push(Event e) {
    std::lock_guard<std::mutex> lk(g_mu);
    if (g_q.size() > 4096) g_q.pop_front();   // hard cap to avoid unbounded growth
    g_q.emplace_back(std::move(e));
}

bool drain(std::vector<Event>& out, size_t max) {
    std::lock_guard<std::mutex> lk(g_mu);
    if (g_q.empty()) return false;
    while (!g_q.empty() && out.size() < max) {
        out.emplace_back(std::move(g_q.front()));
        g_q.pop_front();
    }
    return true;
}
} // namespace
