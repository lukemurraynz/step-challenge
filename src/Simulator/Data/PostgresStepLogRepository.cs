using Npgsql;

namespace StepChallenge.Simulator.Data;

public sealed class PostgresStepLogRepository(NpgsqlDataSource dataSource) : IStepLogRepository
{
    private const string GetParticipantsSql = "SELECT id FROM participants ORDER BY id;";
    private static readonly string[] Names = ["Alex","Bo","Cam","Dee","Eli","Fin","Gus","Hana","Ivy","Jo","Kit","Lou","Max","Nia","Ola","Pat","Quin","Ravi","Sam","Tia"];

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

    public async Task StartContestAsync(int n, CancellationToken ct = default)
    {
        await using var conn = await dataSource.OpenConnectionAsync(ct);
        await using var tx = await conn.BeginTransactionAsync(ct);
        await using (var c = new NpgsqlCommand("TRUNCATE step_logs; DELETE FROM participants;", conn, tx))
            await c.ExecuteNonQueryAsync(ct);
        for (var i = 1; i <= n; i++)
        {
            await using var ins = new NpgsqlCommand(
                "INSERT INTO participants (id,name,team,target) VALUES (@id,@nm,@tm,300000);", conn, tx);
            ins.Parameters.AddWithValue("id", $"p{i:00}");
            ins.Parameters.AddWithValue("nm", $"{Names[(i-1)%Names.Length]} {i}");
            ins.Parameters.AddWithValue("tm", new[]{"Sharks","Eagles","Wolves"}[i%3]);
            await ins.ExecuteNonQueryAsync(ct);
        }
        await using (var s = new NpgsqlCommand("""
            INSERT INTO challenge_state SELECT TRUE,date,day_number,daily_target,cumulative_target FROM daily_targets WHERE day_number=1
            ON CONFLICT (id) DO UPDATE SET today=EXCLUDED.today,day_number=EXCLUDED.day_number,daily_target=EXCLUDED.daily_target,cumulative_target=EXCLUDED.cumulative_target;
            UPDATE contest_state SET participant_count=@n,status='running',started_at=now() WHERE id;
            """, conn, tx)) { s.Parameters.AddWithValue("n", n); await s.ExecuteNonQueryAsync(ct); }
        await tx.CommitAsync(ct);
    }
}