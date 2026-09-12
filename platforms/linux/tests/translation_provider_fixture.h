#pragma once
#include <atomic>
#include <chrono>
#include <cstring>
#include <nlohmann/json.hpp>
#include <poll.h>
#include <stdexcept>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <thread>
#include <unistd.h>

// Local synthetic translations; never contacts a network provider.
class TranslationProviderFixture {
public:
  std::atomic<unsigned> requests{0}, english_greeting_requests{0};
  std::atomic<bool> hold_responses{false};
  explicit TranslationProviderFixture(const std::string &path) : path_(path) {
    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    if (path.size() >= sizeof(address.sun_path))
      throw std::runtime_error("Synthetic translation socket path too long");
    std::memcpy(address.sun_path, path.c_str(), path.size() + 1);
    listener_ = socket(AF_UNIX, SOCK_STREAM, 0);
    if (listener_ < 0 || bind(listener_, reinterpret_cast<sockaddr *>(&address), sizeof(address)) ||
        listen(listener_, 4)) {
      if (listener_ >= 0) close(listener_);
      throw std::runtime_error("Cannot start synthetic translation provider");
    }
    worker_ = std::thread([this] { run(); });
  }
  ~TranslationProviderFixture() {
    stopped_ = true;
    worker_.join();
    close(listener_);
    unlink(path_.c_str());
  }
private:
  std::string path_;
  int listener_ = -1;
  std::atomic<bool> stopped_{false};
  std::thread worker_;
  void run() {
    while (!stopped_) {
      pollfd ready{listener_, POLLIN, 0};
      if (poll(&ready, 1, 10) <= 0) continue;
      const int client = accept(listener_, nullptr, nullptr);
      if (client < 0) continue;
      timeval timeout{1, 0};
      setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
      std::string request;
      char byte;
      while (request.size() < 16384 && recv(client, &byte, 1, 0) == 1 && byte != '\n')
        request += byte;
      const auto value = nlohmann::json::parse(request, nullptr, false);
      if (value.is_object() && value.value("kind", "") == "translation" &&
          value.contains("query") && value["query"].contains("candidates")) {
        auto translations = nlohmann::json::array();
        for (const auto &text : value["query"]["candidates"])
          translations.push_back({{"text", text}, {"translation", "synthetic gloss"}});
        const auto response = nlohmann::json{{"translations", translations}}.dump() + "\n";
        if (value["query"].value("target_language", "") == "en")
          for (const auto &text : value["query"]["candidates"])
            if (text == "你好") ++english_greeting_requests;
        ++requests;
        while (hold_responses && !stopped_)
          std::this_thread::sleep_for(std::chrono::milliseconds(1));
        send(client, response.data(), response.size(), MSG_NOSIGNAL);
      }
      close(client);
    }
  }
};
