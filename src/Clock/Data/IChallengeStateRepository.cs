namespace StepChallenge.Clock.Data;

public interface IChallengeStateRepository
{
    Task AdvanceToNextDayAsync(CancellationToken ct = default);
    Task<bool> SetDayByDateAsync(DateOnly date, CancellationToken ct = default);
    Task<bool> SetDayAsync(int dayNumber, CancellationToken ct = default);
}