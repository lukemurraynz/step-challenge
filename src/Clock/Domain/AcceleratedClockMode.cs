using StepChallenge.Clock.Data;

namespace StepChallenge.Clock.Domain;

public sealed class AcceleratedClockMode(IChallengeStateRepository repo) : IClockMode
{
    public async Task<TickResult> TickAsync(CancellationToken ct = default)
    {
        await repo.AdvanceToNextDayAsync(ct);
        return new TickResult("accelerated", Updated: true);
    }
}