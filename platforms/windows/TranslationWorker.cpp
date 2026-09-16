#include "TranslationWorker.h"

#include "msime_client.h"

#include <curl/curl.h>
#include <nlohmann/json.hpp>

#include <algorithm>
#include <chrono>
#include <ctime>
#include <memory>
#include <stdexcept>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace msime::windows {
namespace {
constexpr auto kDebounce = std::chrono::milliseconds(500);
constexpr size_t kMaximumQueryBytes = 65536;
constexpr size_t kMaximumResponseBytes = 1024 * 1024;
constexpr long kCustomTranslationTimeoutMs = 2500;
constexpr long kTencentTranslationTimeoutMs = 2000;
constexpr long kNiuTransTranslationTimeoutMs = 2500;
constexpr auto kNegativeTranslationTtl = std::chrono::minutes(8);
constexpr size_t kMaximumTranslationCacheEntries = 4096;

struct HttpResponse {
  std::string body;
  std::function<bool()> cancelled;
};

size_t write_response(char *data, size_t size, size_t count, void *context) {
  auto &response = *static_cast<HttpResponse *>(context);
  if (response.cancelled && response.cancelled())
    return 0;
  if (size > kMaximumResponseBytes ||
      response.body.size() > kMaximumResponseBytes ||
      (size != 0 &&
       count > (kMaximumResponseBytes - response.body.size()) / size))
    return 0;
  response.body.append(data, size * count);
  return size * count;
}

int transfer_progress(void *context, curl_off_t, curl_off_t, curl_off_t,
                      curl_off_t) {
  const auto &cancelled = *static_cast<const std::function<bool()> *>(context);
  return cancelled && cancelled() ? 1 : 0;
}

std::unique_ptr<char, decltype(&msime_client_string_free)> owned(char *raw) {
  return {raw, msime_client_string_free};
}

std::optional<nlohmann::json> host_value(char *raw) {
  auto value = owned(raw);
  if (!value)
    return std::nullopt;
  try {
    const auto document = nlohmann::json::parse(value.get());
    if (!document.value("ok", false) || !document.contains("value"))
      return std::nullopt;
    return document.at("value");
  } catch (...) {
    return std::nullopt;
  }
}

std::optional<nlohmann::json> query_document(const std::string &query) {
  if (query.empty() || query.size() > kMaximumQueryBytes)
    return std::nullopt;
  try {
    auto document = nlohmann::json::parse(query);
    if (!document.is_object() || !document.contains("generation") ||
        !document.at("generation").is_number_unsigned() ||
        !document.contains("target_language") ||
        !document.at("target_language").is_string() ||
        !document.contains("candidates") ||
        !document.at("candidates").is_array() ||
        document.at("candidates").empty() ||
        document.at("candidates").size() > 9)
      return std::nullopt;
    for (const auto &candidate : document.at("candidates"))
      if (!candidate.is_object() || !candidate.contains("text") ||
          !candidate.at("text").is_string() ||
          candidate.at("text").get<std::string>().empty() ||
          candidate.at("text").get<std::string>().size() > 4096)
        return std::nullopt;
    return document;
  } catch (...) {
    return std::nullopt;
  }
}

std::optional<std::string> http_request(const nlohmann::json &descriptor,
                                        const std::function<bool()> &cancelled,
                                        bool allow_http, long timeout_ms) {
  try {
    if (!descriptor.is_object() || !descriptor.at("url").is_string())
      return std::nullopt;
    const auto url = descriptor.at("url").get<std::string>();
    const bool https = url.rfind("https://", 0) == 0;
    const bool http = allow_http && url.rfind("http://", 0) == 0;
    if (url.size() > 2048 || (!https && !http) ||
        std::any_of(url.begin(), url.end(),
                    [](unsigned char ch) { return ch < 32 || ch == 127; }))
      return std::nullopt;
    const auto headers = descriptor.value("headers", nlohmann::json::object());
    if (!headers.is_object())
      return std::nullopt;
    static std::once_flag curl_once;
    std::call_once(curl_once, [] { curl_global_init(CURL_GLOBAL_DEFAULT); });
    std::unique_ptr<CURL, decltype(&curl_easy_cleanup)> curl(curl_easy_init(),
                                                             curl_easy_cleanup);
    if (!curl)
      return std::nullopt;
    curl_slist *raw_headers = nullptr;
    std::unique_ptr<curl_slist, decltype(&curl_slist_free_all)> request_headers(
        nullptr, curl_slist_free_all);
    for (auto it = headers.begin(); it != headers.end(); ++it) {
      if (!it.value().is_string() || it.key().size() > 128 ||
          it.value().get<std::string>().size() > 8192)
        return std::nullopt;
      const auto line = it.key() + ": " + it.value().get<std::string>();
      raw_headers = curl_slist_append(raw_headers, line.c_str());
      if (!raw_headers)
        return std::nullopt;
      request_headers.reset(raw_headers);
    }
    HttpResponse response{{}, cancelled};
    curl_easy_setopt(curl.get(), CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl.get(), CURLOPT_PROTOCOLS_STR,
                     allow_http ? "http,https" : "https");
    curl_easy_setopt(curl.get(), CURLOPT_FOLLOWLOCATION, 0L);
    curl_easy_setopt(curl.get(), CURLOPT_CONNECTTIMEOUT_MS, 2500L);
    curl_easy_setopt(curl.get(), CURLOPT_TIMEOUT_MS, timeout_ms);
    curl_easy_setopt(curl.get(), CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(curl.get(), CURLOPT_USERAGENT, "MSIME-Client/1.0");
    curl_easy_setopt(curl.get(), CURLOPT_HTTPHEADER, request_headers.get());
    curl_easy_setopt(curl.get(), CURLOPT_POST, 1L);
    curl_easy_setopt(curl.get(), CURLOPT_WRITEFUNCTION, write_response);
    curl_easy_setopt(curl.get(), CURLOPT_WRITEDATA, &response);
    curl_easy_setopt(curl.get(), CURLOPT_NOPROGRESS, 0L);
    curl_easy_setopt(curl.get(), CURLOPT_XFERINFOFUNCTION, transfer_progress);
    curl_easy_setopt(curl.get(), CURLOPT_XFERINFODATA, &cancelled);
    std::string body;
    if (descriptor.contains("body_utf8")) {
      if (!descriptor.at("body_utf8").is_string())
        return std::nullopt;
      body = descriptor.at("body_utf8").get<std::string>();
    } else if (descriptor.contains("body")) {
      body = descriptor.at("body").dump();
    } else {
      return std::nullopt;
    }
    if (body.size() > kMaximumResponseBytes)
      return std::nullopt;
    curl_easy_setopt(curl.get(), CURLOPT_POSTFIELDS, body.data());
    curl_easy_setopt(curl.get(), CURLOPT_POSTFIELDSIZE_LARGE,
                     static_cast<curl_off_t>(body.size()));
    const auto result = curl_easy_perform(curl.get());
    long status = 0;
    curl_easy_getinfo(curl.get(), CURLINFO_RESPONSE_CODE, &status);
    if (result != CURLE_OK || status < 200 || status >= 300 ||
        (cancelled && cancelled()))
      return std::nullopt;
    return std::move(response.body);
  } catch (...) {
    return std::nullopt;
  }
}

std::optional<std::string>
custom_translation(const nlohmann::json &config, const nlohmann::json &item,
                   const std::function<bool()> &cancelled) {
  const auto request =
      nlohmann::json{{"config", config},
                     {"text", item.at("key")},
                     {"source_language", item.at("source_language")},
                     {"target_language", item.at("target_language")}};
  const auto bytes = request.dump();
  auto descriptor = host_value(msime_client_custom_translation_http_request(
      reinterpret_cast<const uint8_t *>(bytes.data()), bytes.size()));
  if (!descriptor || descriptor->is_null() || cancelled())
    return std::nullopt;
  // The source Windows client permits an explicitly configured HTTP custom
  // translator (useful for a local service).  Keep cloud providers HTTPS-only.
  auto body =
      http_request(*descriptor, cancelled, true, kCustomTranslationTimeoutMs);
  if (!body || cancelled())
    return std::nullopt;
  auto parsed = host_value(msime_client_parse_custom_translation_response(
      reinterpret_cast<const uint8_t *>(body->data()), body->size()));
  if (!parsed || !parsed->is_string() || parsed->get<std::string>().empty())
    return std::nullopt;
  return parsed->get<std::string>();
}

void append_tencent_group(const nlohmann::json &config,
                          const std::vector<nlohmann::json> &items,
                          std::string &translations,
                          const std::function<bool()> &cancelled) {
  if (items.empty() || cancelled())
    return;
  nlohmann::json texts = nlohmann::json::array();
  for (const auto &item : items)
    texts.push_back(item.at("key"));
  const auto request =
      nlohmann::json{{"config", config},
                     {"texts", texts},
                     {"source_language", items.front().at("source_language")},
                     {"target_language", items.front().at("target_language")},
                     {"timestamp", static_cast<int64_t>(std::time(nullptr))}};
  const auto bytes = request.dump();
  auto descriptor = host_value(msime_client_tencent_translation_http_request(
      reinterpret_cast<const uint8_t *>(bytes.data()), bytes.size()));
  if (!descriptor || descriptor->is_null())
    return;
  auto body =
      http_request(*descriptor, cancelled, false, kTencentTranslationTimeoutMs);
  if (!body || cancelled())
    return;
  auto parsed = host_value(msime_client_parse_tencent_translation_response(
      reinterpret_cast<const uint8_t *>(body->data()), body->size(),
      items.size()));
  if (!parsed || !parsed->is_array() || parsed->size() != items.size())
    return;
  try {
    auto output = nlohmann::json::parse(translations);
    for (size_t i = 0; i < items.size(); ++i)
      if (!parsed->at(i).is_null() && parsed->at(i).is_string())
        output.push_back(
            {{"text", items[i].at("text")}, {"translation", parsed->at(i)}});
    translations = output.dump();
  } catch (...) {
  }
}

std::string millisecond_timestamp() {
  const auto now = std::chrono::system_clock::now().time_since_epoch();
  return std::to_string(
      std::chrono::duration_cast<std::chrono::milliseconds>(now).count());
}

void append_niutrans_item(const nlohmann::json &config,
                          const nlohmann::json &item, std::string &translations,
                          const std::function<bool()> &cancelled) {
  if (cancelled())
    return;
  const auto timestamp = millisecond_timestamp();
  const auto request =
      nlohmann::json{{"config", config},
                     {"text", item.at("key")},
                     {"source_language", item.at("source_language")},
                     {"target_language", item.at("target_language")},
                     {"timestamp", timestamp}};
  const auto bytes = request.dump();
  auto descriptor = host_value(msime_client_niutrans_translation_http_request(
      reinterpret_cast<const uint8_t *>(bytes.data()), bytes.size()));
  if (!descriptor || descriptor->is_null() || cancelled())
    return;
  auto body = http_request(*descriptor, cancelled, false,
                           kNiuTransTranslationTimeoutMs);
  if (!body || cancelled())
    return;
  auto parsed = host_value(msime_client_parse_niutrans_translation_response(
      reinterpret_cast<const uint8_t *>(body->data()), body->size()));
  if (!parsed || !parsed->is_string() || parsed->get<std::string>().empty())
    return;
  try {
    auto output = nlohmann::json::parse(translations);
    output.push_back({{"text", item.at("text")}, {"translation", *parsed}});
    translations = output.dump();
  } catch (...) {
  }
}

void persist_english_glosses(const nlohmann::json &query,
                             const std::string &translations) noexcept {
  try {
    if (query.value("target_language", std::string{}) != "en")
      return;
    const auto user_data = query.value("user_data", std::string{});
    if (user_data.empty())
      return;
    const auto values = nlohmann::json::parse(translations);
    if (!values.is_array() || values.empty())
      return;
    const auto request = nlohmann::json{
        {"target_language", "en"},
        {"translations",
         values}}.dump();
    msime_client_string_free(msime_client_translation_gloss_save(
        reinterpret_cast<const uint8_t *>(request.data()), request.size(),
        reinterpret_cast<const uint8_t *>(user_data.data()), user_data.size()));
  } catch (...) {
    // Persistence is an optional display-data side effect. A missing or
    // temporarily unavailable user dictionary must not hide translations.
  }
}

} // namespace

TranslationWorker::TranslationWorker(Completed completed)
    : completed_(std::move(completed)) {
  if (!completed_)
    throw std::invalid_argument("Missing translation completion");
  worker_ = std::thread([this] { run(); });
}

TranslationWorker::~TranslationWorker() { stop(); }

bool TranslationWorker::submit(const FocusLease &lease, std::string query) {
  if (!lease.epoch || !lease.token || query.empty() ||
      query.size() > kMaximumQueryBytes)
    return false;
  std::lock_guard lock(mutex_);
  if (stopping_)
    return false;
  const uint64_t serial = ++next_serial_;
  pending_ = Request{lease, std::move(query), serial};
  latest_serial_.store(serial, std::memory_order_release);
  wake_.notify_one();
  return true;
}

void TranslationWorker::request_stop() {
  stopping_.store(true, std::memory_order_release);
  {
    std::lock_guard lock(mutex_);
    pending_.reset();
  }
  wake_.notify_all();
}

void TranslationWorker::stop() {
  std::lock_guard join(join_mutex_);
  request_stop();
  if (worker_.joinable()) {
    if (worker_.get_id() == std::this_thread::get_id())
      throw std::logic_error("Cannot join translation worker from itself");
    worker_.join();
  }
}

bool TranslationWorker::cancelled(uint64_t serial) const noexcept {
  return stopping_.load(std::memory_order_acquire) ||
         latest_serial_.load(std::memory_order_acquire) != serial;
}

std::optional<TranslationWorker::Result>
TranslationWorker::translate(const Request &request,
                             const std::function<bool()> &cancelled) {
  const auto document = query_document(request.query);
  if (!document || cancelled())
    return std::nullopt;
  try {
    const auto &query = *document;
    const auto generation = query.at("generation").get<uint64_t>();
    auto translations = nlohmann::json::array().dump();
    // The offline English gloss comes from a packaged dictionary, so it is
    // resolved before any provider is consulted and never reaches the network.
    // It is also the only source available when no online provider is
    // configured, which is the usual case.
    if (query.value("english_gloss", false)) {
      const auto resources = query.value("resources", std::string{});
      if (!resources.empty()) {
        auto gloss_request = nlohmann::json{{"generation", generation}};
        const auto user_data = query.value("user_data", std::string{});
        if (!user_data.empty())
          gloss_request["user_data"] = user_data;
        auto gloss_candidates = nlohmann::json::array();
        for (const auto &candidate : query.at("candidates"))
          gloss_candidates.push_back(
              {{"text", candidate.at("text")}, {"source", 0}});
        gloss_request["candidates"] = std::move(gloss_candidates);
        const auto gloss_bytes = gloss_request.dump();
        auto glossed = host_value(msime_client_candidate_gloss_request(
            reinterpret_cast<const uint8_t *>(gloss_bytes.data()),
            gloss_bytes.size(),
            reinterpret_cast<const uint8_t *>(resources.data()),
            resources.size()));
        if (cancelled())
          return std::nullopt;
        if (glossed && glossed->is_object() &&
            glossed->value("translations", nlohmann::json::array()).is_array())
          translations = glossed->at("translations").dump();
      }
      // No gloss for this page. Fall through: an online provider may still be
      // configured, and a page with no dictionary entry is not a failure.
    }
    const auto plan_request = nlohmann::json{
        {"target_language", query.at("target_language")},
        {"candidates", [&] {
           auto candidates = nlohmann::json::array();
           for (const auto &candidate : query.at("candidates"))
             candidates.push_back(
                 {{"text", candidate.at("text")}, {"source", 0}});
           return candidates;
         }()}};
    const auto plan_bytes = plan_request.dump();
    auto plan = host_value(msime_client_custom_translation_plan(
        reinterpret_cast<const uint8_t *>(plan_bytes.data()),
        plan_bytes.size()));
    if (!plan || !plan->is_array() || cancelled())
      return std::nullopt;

    // Keep local dictionary hits and ask an online provider only for misses.
    // This mirrors the source worker's local-first merge behavior instead of
    // treating one offline hit as a complete page.
    std::unordered_set<std::string> translated_texts;
    try {
      for (const auto &entry : nlohmann::json::parse(translations))
        if (entry.is_object() && entry.value("text", std::string{}) != "")
          translated_texts.insert(entry.at("text").get<std::string>());
    } catch (...) {
      return std::nullopt;
    }
    if (plan->empty()) {
      if (translated_texts.empty())
        return std::nullopt;
      return TranslationWorker::Result{request.lease, generation, translations};
    }

    // Translation results are valid across candidate generations. Cache each
    // item independently so one provider miss does not suppress retries for
    // unrelated candidates. Keys deliberately exclude credentials and the
    // generation.
    std::string provider_scope;
    const auto local_result =
        [&]() -> std::optional<TranslationWorker::Result> {
      if (translations == "[]")
        return std::nullopt;
      return TranslationWorker::Result{request.lease, generation, translations};
    };
    const auto niutrans = query.value("niutrans", nlohmann::json(nullptr));
    const auto custom =
        query.value("custom_translation", nlohmann::json(nullptr));
    if (niutrans.is_object() && niutrans.value("enabled", false)) {
      provider_scope = "niutrans";
    } else if (custom.is_object() && custom.value("enabled", false)) {
      provider_scope = "custom:" + custom.value("endpoint", std::string{});
    } else {
      const auto tencent = query.value("tencent_tmt", nlohmann::json(nullptr));
      if (!tencent.is_object() || !tencent.value("enabled", false))
        return local_result();
      provider_scope = "tencent";
    }
    const auto target_language = query.at("target_language");
    const auto item_cache_id = [&](const nlohmann::json &item) {
      return nlohmann::json{
          {"provider", provider_scope},
          {"target_language", target_language},
          {"key", item.at("key")},
          {"direction", item.at("source_language").get<std::string>() + ">" +
                            item.at("target_language").get<std::string>()},
          {"source_language", item.at("source_language")},
          {"item_target_language", item.at("target_language")}}
          .dump();
    };
    std::vector<nlohmann::json> pending;
    for (const auto &item : *plan) {
      if (translated_texts.contains(item.at("text").get<std::string>()))
        continue;
      const auto cache_id = item_cache_id(item);
      if (const auto cached = translation_cache_.find(cache_id);
          cached != translation_cache_.end()) {
        auto output = nlohmann::json::parse(translations);
        output.push_back(
            {{"text", item.at("text")}, {"translation", cached->second}});
        translations = output.dump();
        translated_texts.insert(item.at("text").get<std::string>());
        continue;
      }
      const auto negative = translation_negative_cache_.find(cache_id);
      if (negative != translation_negative_cache_.end()) {
        if (negative->second > std::chrono::steady_clock::now())
          continue;
        translation_negative_cache_.erase(negative);
      }
      pending.push_back(item);
    }

    if (niutrans.is_object() && niutrans.value("enabled", false)) {
      for (const auto &item : pending) {
        if (cancelled())
          return std::nullopt;
        append_niutrans_item(niutrans, item, translations, cancelled);
      }
    } else if (custom.is_object() && custom.value("enabled", false)) {
      for (const auto &item : pending) {
        if (cancelled())
          return std::nullopt;
        if (auto value = custom_translation(custom, item, cancelled)) {
          auto output = nlohmann::json::parse(translations);
          output.push_back(
              {{"text", item.at("text")}, {"translation", *value}});
          translations = output.dump();
        }
      }
    } else {
      const auto tencent = query.value("tencent_tmt", nlohmann::json(nullptr));
      if (!tencent.is_object() || !tencent.value("enabled", false))
        return std::nullopt;
      std::unordered_map<std::string, std::vector<nlohmann::json>> groups;
      for (const auto &item : pending)
        groups[item.at("source_language").get<std::string>() + "\n" +
               item.at("target_language").get<std::string>()]
            .push_back(item);
      for (const auto &[key, items] : groups) {
        (void)key;
        append_tencent_group(tencent, items, translations, cancelled);
      }
    }
    if (cancelled())
      return std::nullopt;
    const auto output = nlohmann::json::parse(translations);
    for (const auto &item : pending) {
      const auto cache_id = item_cache_id(item);
      const auto found =
          std::find_if(output.begin(), output.end(), [&](const auto &entry) {
            return entry.is_object() && entry.value("text", std::string{}) ==
                                            item.at("text").get<std::string>();
          });
      if (found != output.end() &&
          found->value("translation", std::string{}) != std::string{}) {
        const auto value = found->at("translation").get<std::string>();
        if (translation_cache_.size() >= kMaximumTranslationCacheEntries)
          translation_cache_.clear();
        translation_cache_[cache_id] = value;
        translation_negative_cache_.erase(cache_id);
        persist_english_glosses(
            nlohmann::json{
                {"target_language", target_language},
                {"user_data", query.value("user_data", std::string{})}},
            nlohmann::json::array(
                {{{"text", item.at("text")}, {"translation", value}}})
                .dump());
      } else {
        if (translation_negative_cache_.size() >=
            kMaximumTranslationCacheEntries)
          translation_negative_cache_.clear();
        translation_negative_cache_[cache_id] =
            std::chrono::steady_clock::now() + kNegativeTranslationTtl;
      }
    }
    if (output.empty())
      return std::nullopt;
    return TranslationWorker::Result{request.lease, generation, output.dump()};
  } catch (...) {
    return std::nullopt;
  }
}

void TranslationWorker::run() noexcept {
  for (;;) {
    Request request;
    {
      std::unique_lock lock(mutex_);
      wake_.wait(lock, [&] {
        return stopping_.load(std::memory_order_acquire) ||
               pending_.has_value();
      });
      if (stopping_.load(std::memory_order_acquire))
        return;
      request = std::move(*pending_);
      pending_.reset();
      for (;;) {
        const auto deadline = std::chrono::steady_clock::now() + kDebounce;
        if (!wake_.wait_until(lock, deadline, [&] {
              return stopping_.load(std::memory_order_acquire) ||
                     pending_.has_value();
            }))
          break;
        if (stopping_.load(std::memory_order_acquire))
          return;
        request = std::move(*pending_);
        pending_.reset();
      }
    }
    try {
      const auto serial = request.serial;
      const auto cancel = [this, serial] { return cancelled(serial); };
      auto result = translate(request, cancel);
      if (result && !cancel())
        completed_(std::move(*result));
    } catch (...) {
      // Translation is optional and must never stop input.
    }
  }
}
} // namespace msime::windows
