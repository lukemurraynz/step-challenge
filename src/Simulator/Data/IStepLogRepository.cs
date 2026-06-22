namespace StepChallenge.Simulator.Data;

public interface IStepLogRepository
{
    Task<IReadOnlyList<string>> GetParticipantIdsAsync(CancellationToken ct = default);
    Task AddStepsAsync(string participantId, int steps, CancellationToken ct = default);
    Task ResetAsync(CancellationToken ct = default);
}