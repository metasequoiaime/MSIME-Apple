#pragma once
#include <cstddef>
namespace metasequoia::mac {
constexpr size_t NormalizeCandidatePageSize(size_t value) { return value == 5 || value == 7 || value == 9 ? value : 9; }
constexpr size_t CandidatePageSizeForOptionIndex(size_t index) { return index == 0 ? 5 : index == 1 ? 7 : 9; }
constexpr size_t CandidatePageSizeOptionIndex(size_t value) { value = NormalizeCandidatePageSize(value); return value == 5 ? 0 : value == 7 ? 1 : 2; }
}
