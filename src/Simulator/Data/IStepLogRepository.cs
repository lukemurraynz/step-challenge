namespace StepChallenge.Simulator.Data;

public interface IStepLogRepository
{
    Task<IReadOnlyList<string>> GetParticipantIdsAsync(CancellationToken ct = default);
    Task AddStepsAsync(string participantId, int steps, CancellationToken ct = default);
    Task ResetAsync(CancellationToken ct = default);
    Task StartContestAsync(int participants, CancellationToken ct = default);
    Task DeleteContestAsync(CancellationToken ct = default);
    Task<string> GetContestStatusAsync(CancellationToken ct = default);
}