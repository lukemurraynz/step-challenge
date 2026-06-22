using Npgsql;

namespace StepChallenge.Simulator.Data;

public sealed class PostgresStepLogRepository(NpgsqlDataSource dataSource) : IStepLogRepository
{
    private const string GetParticipantsSql = "SELECT id FROM participants ORDER BY id;";

    private const string AddStepsSql = """
        INSERT INTO step_logs (participant_id, steps, log_date)
        VALUES (@pid, @steps, (SELECT today FROM challenge_state));
        """;

    private const string ResetSql = "TRUNCATE step_logs;";

    public async Task<IReadOnlyList<string>> GetParticipantIdsAsync(CancellationToken ct = default)
    {
        await using var cmd = dataSource.CreateCommand(GetParticipantsSql);
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        var ids = new List<string>();
        while (await reader.ReadAsync(ct))
            ids.Add(reader.GetString(0));
        return ids;
    }

    public async Task AddStepsAsync(string participantId, int steps, CancellationToken ct = default)
    {
        await using var cmd = dataSource.CreateCommand(AddStepsSql);
        cmd.Parameters.AddWithValue("pid", participantId);
        cmd.Parameters.AddWithValue("steps", steps);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task ResetAsync(CancellationToken ct = default)
    {
        await using var cmd = dataSource.CreateCommand(ResetSql);
        await cmd.ExecuteNonQueryAsync(ct);
    }
}