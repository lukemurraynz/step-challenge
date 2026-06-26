using StepChallenge.Notifier.Models;

namespace StepChallenge.Notifier.Services;

public sealed class MessageBuilder : IMessageBuilder
{
    public string? Build(ContestEvent contestEvent)
    {
        if (contestEvent.Op != "i") return null;          // only "added" this slice
        if (contestEvent.Payload.After is not { } result) return null;

        return contestEvent.Payload.Source.QueryId switch
        {
            "race-to-goal"  => $"🏁 **{result.Name}** crossed the finish line — {result.Total:N0} steps!",
            "daily-smashed" => $"💪 **{result.Name}** smashed today's goal ({result.Total:N0} steps).",
            "behind-pace"   => $"😟 **{result.Name}** has fallen behind pace.",
            "new-leader"    => null,                       // leader logic = next slice
            _ => null
        };
    }
}