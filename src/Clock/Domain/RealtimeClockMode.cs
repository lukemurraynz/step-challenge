using Microsoft.Extensions.Options;
using StepChallenge.Clock.Data;

namespace StepChallenge.Clock.Domain;

public sealed class RealtimeClockMode(
    IChallengeStateRepository repo,
    TimeProvider clock,
    IOptions<ClockOptions> options) : IClockMode
{
    private readonly TimeZoneInfo _tz =
        TimeZoneInfo.FindSystemTimeZoneById(options.Value.TimeZone);

    public async Task<TickResult> TickAsync(CancellationToken ct = default)
    {
        var nowLocal = TimeZoneInfo.ConvertTime(clock.GetUtcNow(), _tz);
        var today = DateOnly.FromDateTime(nowLocal.DateTime);
        var updated = await repo.SetDayByDateAsync(today, ct);
        return new TickResult("realtime", updated);
    }
}