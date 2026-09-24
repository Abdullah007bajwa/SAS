using K50Bridge.Extensions;
using K50Bridge.Models;
using K50Bridge.Services;
using K50Bridge.Storage;
using Microsoft.AspNetCore.Mvc;

namespace K50Bridge.Controllers;

[ApiController]
[Route("")]
public class DeviceController : ControllerBase
{
    private readonly IDeviceManager _device;
    private readonly BridgeMemoryStore _store;

    public DeviceController(IDeviceManager device, BridgeMemoryStore store)
    {
        _device = device;
        _store = store;
    }

    [HttpGet("health")]
    public IActionResult Health()
    {
        return Ok(new
        {
            bridgeUp = true,
            ok = _device.State == DeviceConnectionState.Online,
            deviceState = _device.State.ToString().ToUpperInvariant(),
            ip = _device.CurrentIp,
            configuredIp = _device.ConfiguredDeviceIp,
            port = _device.CurrentPort,
            lastError = _device.LastError,
        });
    }

    [HttpGet("device/status")]
    public async Task<IActionResult> Status()
    {
        var status = await _device.GetStatusAsync();
        var ok = status.GetType().GetProperty("ok")?.GetValue(status) as bool? ?? false;
        return Ok(new
        {
            bridgeUp = true,
            ok,
            deviceState = _device.State.ToString().ToUpperInvariant(),
            ip = _device.CurrentIp,
            configuredIp = _device.ConfiguredDeviceIp,
            port = _device.CurrentPort,
            lastError = _device.LastError,
            lastPollAt = _device.LastPollAt,
            status
        });
    }

    [HttpPost("device/connect")]
    public async Task<IActionResult> Connect([FromBody] ConnectRequest? body)
    {
        var (success, error) = await _device.ConnectAsync(body?.Ip, body?.Port);
        if (!success)
        {
            return StatusCode(503, new
            {
                success = false,
                error = error ?? "Connect failed",
                errorCode = "DEVICE_OFFLINE",
                retryAfter = 30
            });
        }

        return Ok(new { success = true, connected = true, ip = _device.CurrentIp, port = _device.CurrentPort });
    }

    [HttpPost("device/user/create")]
    public async Task<IActionResult> CreateUser([FromBody] UserRequest request) =>
        (await _device.CreateUserAsync(request)).ToResult(HttpContext);

    [HttpPost("device/user/delete")]
    public async Task<IActionResult> DeleteUser([FromBody] UserRequest request) =>
        (await _device.DeleteUserAsync(request.UserId)).ToResult(HttpContext);

    [HttpPost("device/user/enable")]
    public async Task<IActionResult> EnableUser([FromBody] UserRequest request) =>
        (await _device.EnableUserAsync(request)).ToResult(HttpContext);

    [HttpPost("device/user/suspend")]
    public async Task<IActionResult> SuspendUser([FromBody] UserRequest request) =>
        (await _device.SuspendUserAsync(request)).ToResult(HttpContext);

    [HttpPost("device/fingerprint/enroll")]
    public async Task<IActionResult> Enroll([FromBody] EnrollRequest request) =>
        (await _device.EnrollFingerprintAsync(request)).ToResult(HttpContext);

    [HttpPost("device/fingerprint/verify")]
    public async Task<IActionResult> Verify([FromBody] UserRequest request) =>
        (await _device.VerifyFingerprintAsync(request.UserId)).ToResult(HttpContext);

    [HttpGet("device/attendance")]
    [HttpGet("device/attendance/sync")]
    public IActionResult Attendance([FromQuery] DateTime? since, [FromQuery] int limit = 200)
    {
        var logs = _store.GetAttendance(since, limit).Select(a => new
        {
            userId = a.UserId,
            deviceUserId = a.DeviceUserId,
            timestamp = a.Timestamp.ToUniversalTime().ToString("o"),
            verifyType = a.VerifyType
        });

        return Ok(new
        {
            success = true,
            logs,
            deviceState = _device.State.ToString().ToUpperInvariant()
        });
    }
}
