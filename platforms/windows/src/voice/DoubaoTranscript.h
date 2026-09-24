#pragma once
#include <nlohmann/json.hpp>

#include <string>

namespace msime::windows {
// The transcript in one Doubao response body. bigmodel_async returns "result" as an object; bigmodel_nostream documents it as a list of segments, whose texts are joined in order. MSIME-Windows doubao_asr_client.cpp ExtractTranscript accepts either shape so one parser covers both endpoints.
inline std::string doubao_body_transcript(const nlohmann::json &body) {
  if (!body.is_object() || !body.contains("result"))
    return {};
  const auto &result = body["result"];
  if (result.is_object()) {
    const auto text = result.find("text");
    return text != result.end() && text->is_string() ? text->get<std::string>()
                                                    : std::string();
  }
  if (!result.is_array())
    return {};
  std::string text;
  for (const auto &segment : result) {
    if (!segment.is_object())
      continue;
    const auto part = segment.find("text");
    if (part != segment.end() && part->is_string())
      text += part->get<std::string>();
  }
  return text;
}

// A decoded response message: the transcript at the top level, else inside the legacy "payload_msg" envelope.
inline std::string doubao_transcript(const nlohmann::json &message) {
  auto text = doubao_body_transcript(message);
  if (text.empty() && message.is_object() && message.contains("payload_msg"))
    text = doubao_body_transcript(message["payload_msg"]);
  return text;
}
} // namespace msime::windows
