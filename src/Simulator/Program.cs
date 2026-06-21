using Npgsql;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

var dsn = Environment.GetEnvironmentVariable("PG_DSN")
    ?? "Host=localhost;Username=postgres;Password=postgres;Database=stepup";
var dataSource = NpgsqlDataSource.Create(dsn);

string[] participants = [
    "alice",
    "bob",
    "chloe",
    "dave",
    "erin",
    "finn"
];

// Tunable knobs (1h "how fast it runs") — overridable via env vars
var minSteps = int.TryParse(Environment.GetEnvironmentVariable("TICK_MIN_STEPS"), out var lo) ? lo : 200;
var maxSteps = int.TryParse(Environment.GetEnvironmentVariable("TICK_MAX_STEPS"), out var hi) ? hi : 2500;
var maxPicks = int.TryParse(Environment.GetEnvironmentVariable("TICK_MAX_PARTICIPANTS"), out var mp) ? mp : 3;

var paused = false;

// Dapr cron binding "ticker" calls this on each fire
app.MapPost("/ticker", async () =>
{
    if (paused) return Results.Ok(new { status = "paused" });

    var count = Random.Shared.Next(1, maxPicks + 1);          // 1..maxPicks participants
    var picks = participants.OrderBy(_ => Random.Shared.Next()).Take(count);

    await using var conn = await dataSource.OpenConnectionAsync();
    foreach (var pid in picks)
    {
        var steps = Random.Shared.Next(minSteps, maxSteps + 1);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText =
            "INSERT INTO step_logs (participant_id, steps, log_date) " +
            "VALUES (@pid, @steps, CURRENT_DATE)";
        cmd.Parameters.AddWithValue("pid", pid);
        cmd.Parameters.AddWithValue("steps", steps);
        await cmd.ExecuteNonQueryAsync();
    }
    return Results.Ok(new { inserted = count });
});

// 1h — controls
app.MapPost("/control/pause",  () => { paused = true;  return Results.Ok(new { paused }); });
app.MapPost("/control/resume", () => { paused = false; return Results.Ok(new { paused }); });
app.MapPost("/control/reset", async () =>
{
    await using var conn = await dataSource.OpenConnectionAsync();
    await using var cmd = conn.CreateCommand();
    cmd.CommandText = "TRUNCATE step_logs";
    await cmd.ExecuteNonQueryAsync();
    return Results.Ok(new { reset = true });
});

// 1i (optional) — manual entry for forcing one contest
app.MapPost("/manual", async (ManualEntry e) =>
{
    await using var conn = await dataSource.OpenConnectionAsync();
    await using var cmd = conn.CreateCommand();
    cmd.CommandText =
        "INSERT INTO step_logs (participant_id, steps, log_date) " +
        "VALUES (@pid, @steps, CURRENT_DATE)";
    cmd.Parameters.AddWithValue("pid", e.ParticipantId);
    cmd.Parameters.AddWithValue("steps", e.Steps);
    await cmd.ExecuteNonQueryAsync();
    return Results.Ok(new { ok = true });
});

app.Run();

record ManualEntry(string ParticipantId, int Steps);