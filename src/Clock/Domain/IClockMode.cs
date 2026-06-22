namespace StepChallenge.Clock.Domain;

public interface IClockMode
{
    Task<TickResult> TickAsync(CancellationToken ct = default);
}

public sealed record TickResult(string Mode, bool Updated);