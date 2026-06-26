using StepChallenge.Notifier.Models;
using StepChallenge.Notifier.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddDaprClient();
builder.Services.AddSingleton<IMessageBuilder, MessageBuilder>();
builder.Services.AddSingleton<IDiscordNotifier, DiscordNotifier>();

var app = builder.Build();

app.UseCloudEvents();
app.MapSubscribeHandler();

app.MapPost("/stepup-events", async (
    ContestEvent contestEvent,
    IMessageBuilder messageBuilder,
    IDiscordNotifier discord,
    ILogger<Program> logger,
    CancellationToken cancellationToken) =>
{
    var message = messageBuilder.Build(contestEvent);
    if (message is null) return Results.Ok();

    await discord.SendAsync(message, cancellationToken);
    logger.LogInformation("Posted to Discord: {Message}", message);
    return Results.Ok();
}).WithTopic("stepup-pubsub", "stepup-events");

app.Run();