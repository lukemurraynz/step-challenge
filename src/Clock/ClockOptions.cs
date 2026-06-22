namespace StepChallenge.Clock;

public enum ClockMode { Accelerated, Realtime }

public sealed class ClockOptions
{
    public const string SectionName = "Clock";
    public ClockMode Mode { get; set; } = ClockMode.Accelerated;
    public string TimeZone { get; set; } = "Australia/Sydney";
}