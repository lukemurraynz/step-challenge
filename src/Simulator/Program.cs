using Npgsql;
using StepChallenge.Simulator;
using StepChallenge.Simulator.Data;
using StepChallenge.Simulator.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.Configure<SimulatorOptions>(
    builder.Configuration.GetSection(SimulatorOptions.SectionName));

var dsn = Environment.GetEnvironmentVariable("PG_DSN")
    ?? "Host=localhost;Username=postgres;Password=postgres;Database=stepup";

builder.Services.AddSingleton(NpgsqlDataSource.Create(dsn));
builder.Services.AddSingleton<IStepLogRepository, PostgresStepLogRepository>();
builder.Services.AddSingleton<SimulatorService>();

var app = builder.Build();

// Dapr cron binding "ticker"
app.MapPost("/ticker", async (SimulatorService sim, CancellationToken ct) =>
{
    var inserted = await sim.TickAsync(ct);
    return inserted is null ? Results.Ok(new { status = "paused" }) : Results.Ok(new { inserted });
});

app.MapPost("/control/pause",  (SimulatorService sim) => { sim.Pause();  return Results.Ok(new { sim.IsPaused }); });
app.MapPost("/control/resume", (SimulatorService sim) => { sim.Resume(); return Results.Ok(new { sim.IsPaused }); });
app.MapPost("/control/reset", async (SimulatorService sim, CancellationToken ct) =>
{
    await sim.ResetAsync(ct);
    return Results.Ok(new { reset = true });
});

// query-string bound: /manual?participantId=alice&steps=50000
app.MapPost("/manual", async (string participantId, int steps, SimulatorService sim, CancellationToken ct) =>
{
    await sim.AddManualAsync(participantId, steps, ct);
    return Results.Ok(new { ok = true });
});

app.MapPost("/contest/start", async (int participants, SimulatorService sim, CancellationToken ct) =>
{ 
    await sim.StartContestAsync(participants, ct); return Results.Ok(new { started = participants }); 
});

app.MapPost("/contest/delete", async (SimulatorService sim, CancellationToken ct) =>
{ 
    await sim.DeleteContestAsync(ct); return Results.Ok(new { deleted = true }); 
});

app.MapGet("/contest/status", async (SimulatorService sim, CancellationToken ct) => Results.Ok(new { status = await sim.GetStatusAsync(ct) }));

app.Run();