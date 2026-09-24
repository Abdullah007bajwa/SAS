namespace K50Bridge.Models;

public enum DeviceConnectionState
{
    Offline,
    Online,
    Busy
}

public enum EnrollStatus
{
    Success,
    Pending,
    Failed
}

public sealed class ApiResponse
{
    public bool Success { get; init; }
    public string? Error { get; init; }
    public string? ErrorCode { get; init; }
    public int? RetryAfter { get; init; }
    public string? EnrollState { get; init; }
    public bool RequiresOnDevice { get; init; }
    public bool RemoteModeStarted { get; init; }
    public string? TemplateId { get; init; }
    public string? DeviceUserId { get; init; }
    public string? AppUserId { get; init; }
    public bool Verified { get; init; }
    public Dictionary<string, object?> Extra { get; init; } = new();
}

public sealed class AttendanceRecord
{
    public required string UserId { get; init; }
    public required string DeviceUserId { get; init; }
    public required DateTime Timestamp { get; init; }
    public int VerifyType { get; init; }
}

public sealed class FingerprintTemplateBackup
{
    public int Flag { get; set; }
    public required string Data { get; set; }
}

public sealed class UserMapping
{
    public required string AppUserId { get; set; }
    public required string DeviceUserId { get; set; }
    public required string Name { get; set; }
    public int FingerprintCount { get; set; }

    /// <summary>Fingerprint templates withdrawn on suspend; restored on activate.</summary>
    public Dictionary<int, FingerprintTemplateBackup>? TemplateBackup { get; set; }
}

public sealed class ConnectRequest
{
    public string? Ip { get; set; }
    public int? Port { get; set; }
}

public sealed class UserRequest
{
    public required string UserId { get; set; }
    public string? Name { get; set; }
    public bool Enabled { get; set; } = true;
}

public sealed class EnrollRequest
{
    public required string UserId { get; set; }
    public string? Name { get; set; }
    public int FingerIndex { get; set; } = 0;
    public int TimeoutSec { get; set; } = 45;
}
