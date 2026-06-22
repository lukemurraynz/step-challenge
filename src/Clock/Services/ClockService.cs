using StepChallenge.Clock.Data;
using StepChallenge.Clock.Domain;

namespace StepChallenge.Clock.Services;

public sealed class ClockService(IClockMode mode, IChallengeStateRepository repo)
{
    private volatile bool _paused;

    public bool IsPaused => _paused;
    public void Pause() => _paused = true;
    public void Resume() => _paused = false;

    public Task<TickResult?> TickAsync(CancellationToken ct = default)
        => _paused ? Task.FromResult<TickResult?>(null) : Tick(ct);

    private async Task<TickResult?> Tick(CancellationToken ct) => await mode.TickAsync(ct);

    public Task<bool> GotoAsync(int day, CancellationToken ct = default)
        => repo.SetDayAsync(day, ct);
}