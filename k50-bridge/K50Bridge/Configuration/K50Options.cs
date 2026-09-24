namespace K50Bridge.Configuration;

public sealed class K50Options
{
    public const string SectionName = "K50";

    public string DeviceIp { get; set; } = "192.168.100.18";
    /// <summary>Extra K50 IPs to try if primary is offline (one bridge, failover — not same IP).</summary>
    public string[] FallbackDeviceIps { get; set; } = [];
    public int DevicePort { get; set; } = 4370;
    public int MachineNumber { get; set; } = 1;
    public int ApiPort { get; set; } = 8787;
    public int AttendancePollSeconds { get; set; } = 20;
    public int EnrollTimeoutSeconds { get; set; } = 45;
    public int MaxReconnectAttempts { get; set; } = 3;
    /// <summary>Device communication key (Menu → Comm → PC Connection). 0 = default/off.</summary>
    public int CommPassword { get; set; } = 0;

    public IReadOnlyList<string> AllDeviceIps
    {
        get
        {
            var list = new List<string>();
            if (!string.IsNullOrWhiteSpace(DeviceIp))
                list.Add(DeviceIp.Trim());
            if (FallbackDeviceIps != null)
            {
                foreach (var ip in FallbackDeviceIps)
                {
                    if (string.IsNullOrWhiteSpace(ip)) continue;
                    var trimmed = ip.Trim();
                    if (!list.Contains(trimmed, StringComparer.OrdinalIgnoreCase))
                        list.Add(trimmed);
                }
            }
            return list;
        }
    }
}
