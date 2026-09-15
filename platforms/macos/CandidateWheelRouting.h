#pragma once

namespace msime::mac
{
enum class CandidateWheelAction
{
    None,
    PreviousPage,
    NextPage,
};

constexpr CandidateWheelAction CandidateWheelPageAction(
    double deltaY, bool enabled, bool hasPreviousPage, bool hasNextPage)
{
    if (!enabled || deltaY == 0.0)
        return CandidateWheelAction::None;
    if (deltaY > 0.0 && hasPreviousPage)
        return CandidateWheelAction::PreviousPage;
    if (deltaY < 0.0 && hasNextPage)
        return CandidateWheelAction::NextPage;
    return CandidateWheelAction::None;
}
} // namespace msime::mac
