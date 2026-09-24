// msime-voice-local: on-device recognition in its own process.
//
// An input method process is the worst place to hold a speech model: it is loaded into every app that takes text (macOS IMK, fcitx5), a crash there takes typing down with it, and hundreds of megabytes resident in it count against whatever the host was already allowed. Hosts spawn this helper instead and talk to it over stdin/stdout, one JSON object per line. The protocol is documented in shared/voice/README.md.
//
// `msime-voice-local --model <dir> --wav <file>` transcribes a 16 kHz mono 16-bit WAV file and prints the text, for tests and for checking an installed model by hand.

#include "LocalAsr.h"

#include <msime/voice/stt_service.h>
#include <nlohmann/json.hpp>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <deque>
#include <fstream>
#include <iostream>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

#if defined(_WIN32)
#include <fcntl.h>
#include <io.h>
#endif

namespace {

using msime::voice::LocalAsrOptions;
using msime::voice::LocalAsrSession;

std::mutex output_mutex;

void emit(const nlohmann::json &message) {
  const auto line = message.dump(-1, ' ', false, nlohmann::json::error_handler_t::replace);
  std::lock_guard<std::mutex> lock(output_mutex);
  std::fwrite(line.data(), 1, line.size(), stdout);
  std::fputc('\n', stdout);
  std::fflush(stdout);
}

std::optional<std::vector<float>> decode_pcm16(const std::string &encoded) {
  static const auto table = [] {
    std::array<int, 256> values{};
    values.fill(-1);
    const char *alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    for (int i = 0; i < 64; ++i)
      values[static_cast<unsigned char>(alphabet[i])] = i;
    return values;
  }();
  std::vector<unsigned char> bytes;
  bytes.reserve(encoded.size() * 3 / 4);
  int buffer = 0;
  int bits = 0;
  for (const char character : encoded) {
    if (character == '=')
      break;
    const int value = table[static_cast<unsigned char>(character)];
    if (value < 0)
      return std::nullopt;
    buffer = (buffer << 6) | value;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      bytes.push_back(static_cast<unsigned char>((buffer >> bits) & 0xFF));
    }
  }
  if (bytes.size() % 2 != 0)
    return std::nullopt;
  std::vector<float> samples(bytes.size() / 2);
  for (std::size_t i = 0; i < samples.size(); ++i) {
    const auto sample = static_cast<int16_t>(static_cast<uint16_t>(bytes[2 * i]) | static_cast<uint16_t>(bytes[2 * i + 1]) << 8);
    samples[i] = static_cast<float>(sample) / 32768.0f;
  }
  return samples;
}

std::vector<float> read_wav(const std::string &path) {
  std::ifstream input(path, std::ios::binary);
  if (!input)
    throw std::runtime_error("cannot open " + path);
  std::vector<char> data((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
  auto u16 = [&](std::size_t at) { return static_cast<uint16_t>(static_cast<unsigned char>(data[at]) | static_cast<unsigned char>(data[at + 1]) << 8); };
  auto u32 = [&](std::size_t at) { return static_cast<uint32_t>(u16(at)) | static_cast<uint32_t>(u16(at + 2)) << 16; };
  if (data.size() < 12 || std::memcmp(data.data(), "RIFF", 4) != 0 || std::memcmp(data.data() + 8, "WAVE", 4) != 0)
    throw std::runtime_error(path + " is not a WAV file");
  std::size_t at = 12;
  bool format_ok = false;
  while (at + 8 <= data.size()) {
    const auto size = u32(at + 4);
    if (std::memcmp(data.data() + at, "fmt ", 4) == 0 && at + 8 + 16 <= data.size())
      format_ok = u16(at + 8) == 1 && u16(at + 10) == 1 && u32(at + 12) == 16000 && u16(at + 22) == 16;
    if (std::memcmp(data.data() + at, "data", 4) == 0) {
      if (!format_ok)
        throw std::runtime_error(path + " is not 16 kHz mono 16-bit PCM");
      const std::size_t count = std::min<std::size_t>(size, data.size() - at - 8) / 2;
      std::vector<float> samples(count);
      for (std::size_t i = 0; i < count; ++i)
        samples[i] = static_cast<float>(static_cast<int16_t>(u16(at + 8 + 2 * i))) / 32768.0f;
      return samples;
    }
    at += 8 + size + (size & 1);
  }
  throw std::runtime_error(path + " has no audio");
}

struct Command {
  nlohmann::json message;
};

class Server {
public:
  explicit Server(std::chrono::seconds idle_exit) : idle_exit_(idle_exit) {}

  int run() {
    emit({{"type", "hello"}, {"version", 1}, {"available", msime::voice::sherpa_runtime_available()}, {"error", msime::voice::sherpa_runtime_error()}});
    std::thread reader([this] { read_loop(); });
    work_loop();
    reader.detach();
    return 0;
  }

private:
  void read_loop() {
    std::string line;
    while (std::getline(std::cin, line)) {
      if (line.empty())
        continue;
      nlohmann::json message;
      try {
        message = nlohmann::json::parse(line);
      } catch (const nlohmann::json::exception &) {
        emit({{"type", "error"}, {"message", "malformed request"}});
        continue;
      }
      // Cancellation takes effect in the middle of a decode, so it cannot wait its turn in the queue.
      if (message.value("op", std::string()) == "cancel") {
        std::lock_guard<std::mutex> lock(mutex_);
        if (cancelled_)
          cancelled_->store(true);
      }
      std::lock_guard<std::mutex> lock(mutex_);
      queue_.push_back({std::move(message)});
      ready_.notify_one();
    }
    std::lock_guard<std::mutex> lock(mutex_);
    closed_ = true;
    ready_.notify_one();
  }

  void work_loop() {
    // Release a loaded model after this long without a session; the process itself exits after idle_exit_.
    const auto release_after = std::min<std::chrono::steady_clock::duration>(idle_exit_, std::chrono::seconds(120));
    auto last_activity = std::chrono::steady_clock::now();
    for (;;) {
      std::unique_lock<std::mutex> lock(mutex_);
      ready_.wait_for(lock, std::chrono::seconds(5), [this] { return closed_ || !queue_.empty(); });
      if (queue_.empty()) {
        if (closed_)
          return;
        lock.unlock();
        const auto idle = std::chrono::steady_clock::now() - last_activity;
        if (!session_) {
          msime::voice::release_idle_local_models(release_after);
          if (idle_exit_.count() > 0 && idle >= idle_exit_)
            return;
        }
        continue;
      }
      auto command = std::move(queue_.front());
      queue_.pop_front();
      lock.unlock();
      last_activity = std::chrono::steady_clock::now();
      handle(command.message);
    }
  }

  void handle(const nlohmann::json &message) {
    const auto op = message.value("op", std::string());
    const auto id = message.value("id", nlohmann::json());
    try {
      if (op == "start") {
        LocalAsrOptions options;
        options.model_dir = message.at("model").get<std::string>();
        options.language = message.value("language", std::string());
        options.threads = message.value("threads", 0);
        if (message.contains("hotwords"))
          options.hotwords = message.at("hotwords").get<std::vector<std::string>>();
        auto cancelled = std::make_shared<std::atomic_bool>(false);
        {
          std::lock_guard<std::mutex> lock(mutex_);
          cancelled_ = cancelled;
        }
        session_.reset();
        session_ = std::make_unique<LocalAsrSession>(
            options, [id](const std::string &text) { emit({{"type", "partial"}, {"id", id}, {"text", text}}); }, cancelled);
        session_id_ = id;
        emit({{"type", "started"}, {"id", id}});
      } else if (op == "audio") {
        if (!session_)
          return;
        const auto samples = decode_pcm16(message.at("pcm16").get<std::string>());
        if (!samples)
          throw std::runtime_error("audio is not base64 16-bit PCM");
        session_->accept(samples->data(), samples->size());
      } else if (op == "finish") {
        if (!session_)
          return;
        auto session = std::move(session_);
        const auto text = session->finish();
        emit({{"type", "final"}, {"id", session_id_}, {"text", text}});
      } else if (op == "cancel") {
        if (session_) {
          session_.reset();
          emit({{"type", "cancelled"}, {"id", session_id_}});
        }
      } else if (op == "release") {
        msime::voice::release_local_models();
      } else if (op == "ping") {
        emit({{"type", "pong"}, {"id", id}, {"available", msime::voice::sherpa_runtime_available()}});
      } else {
        throw std::runtime_error("unknown op");
      }
    } catch (const std::exception &error) {
      const bool cancelled = cancelled_ && cancelled_->load();
      session_.reset();
      emit({{"type", cancelled ? "cancelled" : "error"}, {"id", op == "start" ? id : session_id_}, {"message", error.what()}});
    }
  }

  std::chrono::seconds idle_exit_;
  std::mutex mutex_;
  std::condition_variable ready_;
  std::deque<Command> queue_;
  bool closed_ = false;
  std::shared_ptr<std::atomic_bool> cancelled_;
  std::unique_ptr<LocalAsrSession> session_;
  nlohmann::json session_id_;
};

} // namespace

int main(int argc, char **argv) {
#if defined(_WIN32)
  _setmode(_fileno(stdout), _O_BINARY);
  _setmode(_fileno(stdin), _O_BINARY);
#endif
  std::string model;
  std::string wav;
  std::string language;
  std::vector<std::string> hotwords;
  std::chrono::seconds idle_exit(600);
  for (int i = 1; i < argc; ++i) {
    const std::string argument = argv[i];
    auto value = [&]() -> std::string {
      if (i + 1 >= argc) {
        std::fprintf(stderr, "%s needs a value\n", argument.c_str());
        std::exit(2);
      }
      return argv[++i];
    };
    if (argument == "--model")
      model = value();
    else if (argument == "--wav")
      wav = value();
    else if (argument == "--language")
      language = value();
    else if (argument == "--hotword")
      hotwords.push_back(value());
    else if (argument == "--runtime")
      msime::voice::set_sherpa_library_path(value());
    else if (argument == "--idle-exit")
      idle_exit = std::chrono::seconds(std::stoi(value()));
    else {
      std::fprintf(stderr, "usage: msime-voice-local [--runtime <library>] [--idle-exit <seconds>] [--model <dir> --wav <file> [--language <tag>] [--hotword <word>]...]\n");
      return 2;
    }
  }
  if (!wav.empty()) {
    try {
      LocalAsrOptions options;
      options.model_dir = model;
      options.language = language;
      options.hotwords = hotwords;
      const auto text = msime::voice::recognize_local_model(read_wav(wav), options, nullptr);
      std::fwrite(text.data(), 1, text.size(), stdout);
      std::fputc('\n', stdout);
      return 0;
    } catch (const std::exception &error) {
      std::fprintf(stderr, "%s\n", error.what());
      return 1;
    }
  }
  return Server(idle_exit).run();
}
