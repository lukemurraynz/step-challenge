using Npgsql;
using StepChallenge.Clock;
using StepChallenge.Clock.Data;
using StepChallenge.Clock.Domain;
using StepChallenge.Clock.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.Configure<ClockOptions>(
    builder.Configuration.GetSection(ClockOptions.SectionName));
var options = builder.Configuration.GetSection(ClockOptions.SectionName).Get<ClockOptions>() ?? new();

var dsn = Environment.GetEnvironmentVariable("PG_DSN")
    ?? "Host=localhost;Username=postgres;Password=postgres;Database=stepup";

builder.Services.AddSingleton(NpgsqlDataSource.Create(dsn));
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton<IChallengeStateRepository, PostgresChallengeStateRepository>();

// Strategy selection — the one place that knows about both modes
if (options.Mode == ClockMode.Realtime)
    builder.Services.AddSingleton<IClockMode, RealtimeClockMode>();
else
    builder.Services.AddSingleton<IClockMode, AcceleratedClockMode>();

builder.Services.AddSingleton<ClockService>();

var app = builder.Build();

app.MapPost("/clock-cron", async (ClockService clock, CancellationToken ct) =>
{
    var result = await clock.TickAsync(ct);
    return result is null ? Results.Ok(new { status = "paused" }) : Results.Ok(result);
});

app.MapPost("/control/pause",  (ClockService clock) => { clock.Pause();  return Results.Ok(new { clock.IsPaused }); });
app.MapPost("/control/resume", (ClockService clock) => { clock.Resume(); return Results.Ok(new { clock.IsPaused }); });
app.MapPost("/control/goto", async (int day, ClockService clock, CancellationToken ct) =>
    await clock.GotoAsync(day, ct)
        ? Results.Ok(new { day })
        : Results.NotFound(new { error = $"day {day} not in daily_targets" }));

app.Run();