using K50Bridge.Configuration;
using K50Bridge.Models;
using K50Bridge.Services;

namespace K50Bridge.Services;

public sealed class AttendancePollingService : BackgroundService
{
    private readonly IDeviceManager _device;
    private readonly K50Options _options;
    private readonly ILogger<AttendancePollingService> _logger;

    public AttendancePollingService(
        IDeviceManager device,
        Microsoft.Extensions.Options.IOptions<K50Options> options,
        ILogger<AttendancePollingService> logger)
    {
        _device = device;
        _options = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var interval = TimeSpan.FromSeconds(Math.Clamp(_options.AttendancePollSeconds, 10, 30));
        _logger.LogInformation("Attendance polling every {Seconds}s", interval.TotalSeconds);

        // Let Kestrel bind :8787 before the first (slow) Connect_Net attempt.
        await Task.Delay(TimeSpan.FromSeconds(3), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                if (_device.State == DeviceConnectionState.Online)
                {
                    var inserted = await _device.SyncAttendanceAsync(stoppingToken);
                    if (inserted > 0)
                        _logger.LogInformation("Attendance sync inserted {Count} new logs", inserted);
                }
                else if (_device.State == DeviceConnectionState.Offline)
                {
                    await _device.ConnectAsync(ct: stoppingToken);
                }
                // Skip polling while enroll/other SDK work holds the device (Busy).
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Attendance poll failed");
            }

            await Task.Delay(interval, stoppingToken);
        }
    }
}
