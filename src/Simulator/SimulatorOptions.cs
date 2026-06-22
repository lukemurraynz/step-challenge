namespace StepChallenge.Simulator;

public sealed class SimulatorOptions
{
    public const string SectionName = "Simulator";
    public int MinSteps { get; set; } = 200;
    public int MaxSteps { get; set; } = 2500;
    public int MaxParticipants { get; set; } = 3;
}