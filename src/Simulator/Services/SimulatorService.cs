using Microsoft.Extensions.Options;
using StepChallenge.Simulator.Data;

namespace StepChallenge.Simulator.Services;

public sealed class SimulatorService(IStepLogRepository repo, IOptions<SimulatorOptions> options)
{
    private readonly SimulatorOptions _opts = options.Value;
    private volatile bool _paused;

    public bool IsPaused => _paused;
    public void Pause() => _paused = true;
    public void Resume() => _paused = false;

    public async Task<int?> TickAsync(CancellationToken ct = default)
    {
        if (_paused) return null;
        if (await repo.GetContestStatusAsync(ct) != "running") return 0;

        var roster = await repo.GetParticipantIdsAsync(ct);
        if (roster.Count == 0) return 0;

        var maxPicks = Math.Min(_opts.MaxParticipants, roster.Count);
        var count = Random.Shared.Next(1, maxPicks + 1);
        var picks = roster.OrderBy(_ => Random.Shared.Next()).Take(count);

        foreach (var pid in picks)
        {
            var steps = Random.Shared.Next(_opts.MinSteps, _opts.MaxSteps + 1);
            await repo.AddStepsAsync(pid, steps, ct);
        }
        return count;
    }

    public async Task ResetAsync(CancellationToken ct = default) => await repo.ResetAsync(ct);

    public async Task AddManualAsync(string participantId, int steps, CancellationToken ct = default)
        => await repo.AddStepsAsync(participantId, steps, ct);

    public async Task StartContestAsync(int participants, CancellationToken ct = default)
        => await repo.StartContestAsync(Math.Clamp(participants, _opts.MinN, _opts.MaxN), ct);

    public async Task DeleteContestAsync(CancellationToken ct = default) => await repo.DeleteContestAsync(ct);

    public async Task<string> GetStatusAsync(CancellationToken ct = default) => await repo.GetContestStatusAsync(ct);
}