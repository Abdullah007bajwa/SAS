namespace K50Bridge.Services;

public sealed class SdkCallLog
{
    public required string Method { get; init; }
    public object? Parameters { get; init; }
    public object? Result { get; init; }
    public long DurationMs { get; init; }
    public string StateBefore { get; init; } = "";
    public string StateAfter { get; init; } = "";
    public string? Error { get; init; }
}

public interface ISdkLogger
{
    void Log(SdkCallLog entry);
}

public sealed class SdkLogger : ISdkLogger
{
    private readonly ILogger<SdkLogger> _logger;

    public SdkLogger(ILogger<SdkLogger> logger) => _logger = logger;

    public void Log(SdkCallLog entry)
    {
        if (entry.Error != null)
        {
            _logger.LogError(
                "SDK {Method} failed in {DurationMs}ms state {Before}->{After} params {@Params} result {@Result} error {Error}",
                entry.Method,
                entry.DurationMs,
                entry.StateBefore,
                entry.StateAfter,
                entry.Parameters,
                entry.Result,
                entry.Error);
            return;
        }

        if (entry.Result is bool b && !b)
        {
            _logger.LogWarning(
                "SDK {Method} returned false in {DurationMs}ms state {Before}->{After} params {@Params}",
                entry.Method,
                entry.DurationMs,
                entry.StateBefore,
                entry.StateAfter,
                entry.Parameters);
            return;
        }

        if (entry.Result is ValueTuple<bool, string?> tuple && !tuple.Item1)
        {
            _logger.LogWarning(
                "SDK {Method} failed in {DurationMs}ms state {Before}->{After} params {@Params} error {Error}",
                entry.Method,
                entry.DurationMs,
                entry.StateBefore,
                entry.StateAfter,
                entry.Parameters,
                tuple.Item2);
            return;
        }

        if (IsRoutinePoll(entry.Method))
        {
            _logger.LogDebug(
                "SDK {Method} ok in {DurationMs}ms",
                entry.Method,
                entry.DurationMs);
            return;
        }

        _logger.LogInformation(
            "SDK {Method} ok in {DurationMs}ms state {Before}->{After} params {@Params} result {@Result}",
            entry.Method,
            entry.DurationMs,
            entry.StateBefore,
            entry.StateAfter,
            entry.Parameters,
            entry.Result);
    }

    private static bool IsRoutinePoll(string method) =>
        method is "ReadAllGLogData" or "SyncAttendance" or "SSR_GetGeneralLogData";
}
