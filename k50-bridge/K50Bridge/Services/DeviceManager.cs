using System.Diagnostics;
using K50Bridge.Configuration;
using K50Bridge.Models;
using K50Bridge.Storage;
using Microsoft.Extensions.Options;
using zkemkeeper;

namespace K50Bridge.Services;

public interface IDeviceManager
{
    DeviceConnectionState State { get; }
    string? LastError { get; }
    DateTime? LastPollAt { get; }
    string CurrentIp { get; }
    int CurrentPort { get; }
    string ConfiguredDeviceIp { get; }

    Task<(bool Success, string? Error)> ConnectAsync(string? ip = null, int? port = null, CancellationToken ct = default);
    Task DisconnectAsync(CancellationToken ct = default);
    Task<ApiResponse> CreateUserAsync(UserRequest request, CancellationToken ct = default);
    Task<ApiResponse> DeleteUserAsync(string userId, CancellationToken ct = default);
    Task<ApiResponse> EnableUserAsync(UserRequest request, CancellationToken ct = default);
    Task<ApiResponse> SuspendUserAsync(UserRequest request, CancellationToken ct = default);
    Task<ApiResponse> EnrollFingerprintAsync(EnrollRequest request, CancellationToken ct = default);
    Task<ApiResponse> VerifyFingerprintAsync(string userId, CancellationToken ct = default);
    Task<int> SyncAttendanceAsync(CancellationToken ct = default);
    Task<object> GetStatusAsync(CancellationToken ct = default);
}

public sealed class DeviceManager : IDeviceManager, IDisposable
{
    private readonly CZKEMClass _zk = new();
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly IOptionsMonitor<K50Options> _optionsMonitor;
    private readonly BridgeMemoryStore _store;
    private readonly AttendancePushBroadcaster _push;
    private readonly ISdkLogger _sdkLog;
    private readonly ILogger<DeviceManager> _logger;

    private K50Options Options => _optionsMonitor.CurrentValue;

    private TaskCompletionSource<EnrollFingerEventArgs>? _enrollTcs;
    private string? _enrollTargetUserId;
    private volatile bool _enrollFingerSucceeded;
    private DeviceConnectionState _state = DeviceConnectionState.Offline;
    private string? _lastError;
    private DateTime? _lastPollAt;
    private string _ip;
    private int _port;
    private bool _eventsRegistered;

    public DeviceManager(
        IOptionsMonitor<K50Options> optionsMonitor,
        BridgeMemoryStore store,
        AttendancePushBroadcaster push,
        ISdkLogger sdkLog,
        ILogger<DeviceManager> logger)
    {
        _optionsMonitor = optionsMonitor;
        _store = store;
        _push = push;
        _sdkLog = sdkLog;
        _logger = logger;
        _ip = Options.DeviceIp;
        _port = Options.DevicePort;
        WireEvents();
    }

    public DeviceConnectionState State => _state;
    public string? LastError => _lastError;
    public DateTime? LastPollAt => _lastPollAt;
    public string CurrentIp => _ip;
    public int CurrentPort => _port;
    public string ConfiguredDeviceIp => Options.DeviceIp;

    private void WireEvents()
    {
        _zk.OnEnrollFingerEx += Zk_OnEnrollFingerEx;
        _zk.OnEnrollFinger += Zk_OnEnrollFinger;
        _zk.OnConnected += Zk_OnConnected;
        _zk.OnDisConnected += Zk_OnDisConnected;
        _zk.OnAttTransactionEx += Zk_OnAttTransactionEx;
        _zk.OnAttTransaction += Zk_OnAttTransaction;
    }

    private void Zk_OnConnected()
    {
        _logger.LogInformation("ZK event OnConnected");
    }

    private void Zk_OnDisConnected()
    {
        _logger.LogWarning("ZK event OnDisConnected");
        _state = DeviceConnectionState.Offline;
    }

    private void Zk_OnAttTransactionEx(
        string enrollNumber,
        int isInValid,
        int attState,
        int verifyMethod,
        int year,
        int month,
        int day,
        int hour,
        int minute,
        int second,
        int workCode)
    {
        HandleRealtimeAttendance(
            enrollNumber,
            isInValid,
            verifyMethod,
            year,
            month,
            day,
            hour,
            minute,
            second);
    }

    private void Zk_OnAttTransaction(
        int enrollNumber,
        int isInValid,
        int attState,
        int verifyMethod,
        int year,
        int month,
        int day,
        int hour,
        int minute,
        int second)
    {
        HandleRealtimeAttendance(
            enrollNumber.ToString(),
            isInValid,
            verifyMethod,
            year,
            month,
            day,
            hour,
            minute,
            second);
    }

    private void HandleRealtimeAttendance(
        string enrollNumber,
        int isInValid,
        int verifyMethod,
        int year,
        int month,
        int day,
        int hour,
        int minute,
        int second)
    {
        if (isInValid != 0) return;

        try
        {
            var ts = new DateTime(year, month, day, hour, minute, second);
            if (TryRecordAndPushAttendance(enrollNumber, verifyMethod, ts))
            {
                _logger.LogInformation(
                    "Real-time attendance push user={User} at {Time} verify={Verify}",
                    enrollNumber,
                    ts,
                    verifyMethod);
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Real-time attendance failed for user={User}", enrollNumber);
        }
    }

    private bool TryRecordAndPushAttendance(string enrollNumber, int verifyMode, DateTime timestamp)
    {
        var mapping = _store.GetUserByDeviceId(enrollNumber) ?? _store.GetUser(enrollNumber);
        if (mapping?.TemplateBackup is { Count: > 0 })
            return false;

        var appUserId = mapping?.AppUserId ?? enrollNumber;
        var record = new AttendanceRecord
        {
            UserId = appUserId,
            DeviceUserId = enrollNumber,
            Timestamp = timestamp,
            VerifyType = verifyMode
        };

        if (!_store.AddAttendance(record))
            return false;

        _push.Broadcast(record);
        return true;
    }

    private void Zk_OnEnrollFingerEx(string enrollNumber, int fingerIndex, int actionResult, int templateLength)
    {
        _logger.LogInformation(
            "OnEnrollFingerEx user={User} finger={Finger} result={Result} len={Len}",
            enrollNumber, fingerIndex, actionResult, templateLength);

        if (!UserIdsMatch(_enrollTargetUserId, enrollNumber)) return;

        var args = new EnrollFingerEventArgs(enrollNumber, fingerIndex, actionResult, templateLength, true);
        if (IsEnrollEventSuccess(args))
            _enrollFingerSucceeded = true;

        _enrollTcs?.TrySetResult(args);
    }

    private void Zk_OnEnrollFinger(int enrollNumber, int fingerIndex, int actionResult, int templateLength)
    {
        _logger.LogInformation(
            "OnEnrollFinger uid={Uid} finger={Finger} result={Result} len={Len}",
            enrollNumber, fingerIndex, actionResult, templateLength);

        var target = _enrollTargetUserId ?? "";
        if (!UserIdsMatch(target, enrollNumber.ToString())) return;

        var args = new EnrollFingerEventArgs(enrollNumber.ToString(), fingerIndex, actionResult, templateLength, false);
        if (IsEnrollEventSuccess(args))
            _enrollFingerSucceeded = true;

        _enrollTcs?.TrySetResult(args);
    }

    public async Task<(bool Success, string? Error)> ConnectAsync(
        string? ip = null,
        int? port = null,
        CancellationToken ct = default)
    {
        await _gate.WaitAsync(ct);
        try
        {
            return await ConnectCoreAsync(ip, port, ct);
        }
        finally
        {
            _gate.Release();
        }
    }

    /// <summary>Connect while caller already holds <see cref="_gate"/> (avoid re-entrant deadlock).</summary>
    private async Task<(bool Success, string? Error)> ConnectCoreAsync(
        string? ip = null,
        int? port = null,
        CancellationToken ct = default)
    {
        if (port.HasValue) _port = port.Value;

        var candidates = new List<string>();
        if (!string.IsNullOrWhiteSpace(ip))
            candidates.Add(ip.Trim());
        else
        {
            var configuredPrimary = Options.DeviceIp.Trim();
            if (_state == DeviceConnectionState.Online &&
                !string.Equals(_ip, configuredPrimary, StringComparison.OrdinalIgnoreCase))
            {
                _logger.LogInformation(
                    "appsettings.json IP changed ({OldIp} -> {NewIp}); reconnecting",
                    _ip,
                    configuredPrimary);
                try { _zk.Disconnect(); } catch { /* ignore */ }
                _state = DeviceConnectionState.Offline;
            }

            candidates.AddRange(Options.AllDeviceIps);
        }

        if (candidates.Count == 0)
            candidates.Add(_ip);

        string? lastError = null;
        foreach (var candidate in candidates)
        {
            ct.ThrowIfCancellationRequested();
            var attemptIp = candidate.Trim();
            var result = await TryConnectOnceAsync(attemptIp, _port, ct);
            if (result.Success)
            {
                _ip = attemptIp;
                return result;
            }
            lastError = result.Error;
            _logger.LogWarning("Connect failed for {Ip}: {Error}", attemptIp, lastError);
        }

        _state = DeviceConnectionState.Offline;
        _lastError = lastError;
        return (false, lastError);
    }

    private async Task<(bool Success, string? Error)> TryConnectOnceAsync(
        string ip,
        int port,
        CancellationToken ct)
    {
        return await RunSdkAsync("Connect_Net", new { ip, port, Options.CommPassword }, () =>
        {
            if (_state == DeviceConnectionState.Online &&
                string.Equals(_ip, ip, StringComparison.OrdinalIgnoreCase))
                return (true, null);

            try { _zk.Disconnect(); } catch { /* ignore */ }
            _state = DeviceConnectionState.Offline;

            if (!ZkSdkHelper.TryConnect(_zk, ip, port, Options.CommPassword, out var connectError))
            {
                _state = DeviceConnectionState.Offline;
                return (false, connectError);
            }

            if (!_eventsRegistered)
            {
                var regOk = _zk.RegEvent(Options.MachineNumber, 65535);
                LogSdkOnly("RegEvent", new { Options.MachineNumber, mask = 65535 }, regOk);
                _eventsRegistered = true;
            }

            _state = DeviceConnectionState.Online;
            _lastError = null;
            return (true, null);
        }, ct);
    }

    public async Task DisconnectAsync(CancellationToken ct = default)
    {
        await _gate.WaitAsync(ct);
        try
        {
            RunSdkSync("Disconnect", null, () =>
            {
                _zk.Disconnect();
                _state = DeviceConnectionState.Offline;
                return true;
            });
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<ApiResponse> CreateUserAsync(UserRequest request, CancellationToken ct = default)
    {
        await _gate.WaitAsync(ct);
        try
        {
            var connect = await EnsureConnectedInternalAsync();
            if (!connect.Success)
                return Fail("DEVICE_OFFLINE", connect.Error ?? "Not connected");

            _state = DeviceConnectionState.Busy;
            var deviceUserId = MapToDeviceUserId(request.UserId);
            var name = string.IsNullOrWhiteSpace(request.Name) ? request.UserId : request.Name!;

            var setOk = SetUserAccessOnDevice(deviceUserId, name, request.Enabled);

            if (!setOk)
                return Fail("SDK_ERROR", "SSR_SetUserInfo failed");

            if (!VerifyUserOnDevice(deviceUserId, out _))
                return Fail("VERIFY_FAILED", "User not found on device after create");

            _store.UpsertUser(new UserMapping
            {
                AppUserId = request.UserId,
                DeviceUserId = deviceUserId,
                Name = name,
                FingerprintCount = _store.GetUser(request.UserId)?.FingerprintCount ?? 0
            });

            return Ok(new { appUserId = request.UserId, deviceUserId, verified = true });
        }
        finally
        {
            if (_state == DeviceConnectionState.Busy) _state = DeviceConnectionState.Online;
            _gate.Release();
        }
    }

    public async Task<ApiResponse> DeleteUserAsync(string userId, CancellationToken ct = default)
    {
        await _gate.WaitAsync(ct);
        try
        {
            var connect = await EnsureConnectedInternalAsync();
            if (!connect.Success)
                return Fail("DEVICE_OFFLINE", connect.Error ?? "Not connected");

            _state = DeviceConnectionState.Busy;
            var deviceUserId = ResolveDeviceUserId(userId);
            var ok = RunSdkSync("SSR_DeleteEnrollData", new { deviceUserId }, () =>
                _zk.SSR_DeleteEnrollData(Options.MachineNumber, deviceUserId, 12));

            if (!ok)
            {
                ok = RunSdkSync("DeleteUserInfoEx", new { deviceUserId }, () =>
                {
                    if (!int.TryParse(deviceUserId, out var enrollNumber))
                        return false;
                    return _zk.DeleteUserInfoEx(Options.MachineNumber, enrollNumber);
                });
            }

            _store.RemoveUser(userId);
            return Ok(new { deleted = ok, appUserId = userId });
        }
        finally
        {
            if (_state == DeviceConnectionState.Busy) _state = DeviceConnectionState.Online;
            _gate.Release();
        }
    }

    public async Task<ApiResponse> EnableUserAsync(UserRequest request, CancellationToken ct = default)
    {
        await _gate.WaitAsync(ct);
        try
        {
            var connect = await EnsureConnectedInternalAsync();
            if (!connect.Success)
                return Fail("DEVICE_OFFLINE", connect.Error ?? "Not connected");

            _state = DeviceConnectionState.Busy;
            var deviceUserId = ResolveDeviceUserId(request.UserId);
            var name = string.IsNullOrWhiteSpace(request.Name) ? request.UserId : request.Name!;

            if (!VerifyUserOnDevice(deviceUserId, out var existingName))
            {
                var create = CreateUserInternal(request.UserId, name, enabled: true);
                return create.Success
                    ? Ok(new { enabled = true, appUserId = request.UserId, deviceUserId })
                    : create;
            }

            if (!string.IsNullOrWhiteSpace(existingName))
                name = existingName;

            if (!SetUserAccessOnDevice(deviceUserId, name, enabled: true))
                return Fail("SDK_ERROR", "Enable failed");

            var templatesRestored = RestoreFingerprintTemplates(deviceUserId, request.UserId);

            var mapping = _store.GetUser(request.UserId);
            if (mapping != null)
            {
                mapping.Name = name;
            }
            else
            {
                _store.UpsertUser(new UserMapping
                {
                    AppUserId = request.UserId,
                    DeviceUserId = deviceUserId,
                    Name = name,
                    FingerprintCount = 0
                });
            }

            return Ok(new
            {
                enabled = true,
                appUserId = request.UserId,
                deviceUserId,
                templatesRestored
            });
        }
        finally
        {
            if (_state == DeviceConnectionState.Busy) _state = DeviceConnectionState.Online;
            _gate.Release();
        }
    }

    public async Task<ApiResponse> SuspendUserAsync(UserRequest request, CancellationToken ct = default)
    {
        await _gate.WaitAsync(ct);
        try
        {
            var connect = await EnsureConnectedInternalAsync();
            if (!connect.Success)
                return Fail("DEVICE_OFFLINE", connect.Error ?? "Not connected");

            _state = DeviceConnectionState.Busy;
            var deviceUserId = ResolveDeviceUserId(request.UserId);
            var name = string.IsNullOrWhiteSpace(request.Name) ? request.UserId : request.Name!;

            if (!VerifyUserOnDevice(deviceUserId, out var existingName))
                return Fail("VERIFY_FAILED", "User not on device");

            if (!string.IsNullOrWhiteSpace(existingName))
                name = existingName;

            // K50 firmware often ignores Enabled/validity — withdraw templates so scan cannot match.
            var templatesBackedUp = BackupFingerprintTemplates(deviceUserId, request.UserId);
            var templatesRemoved = false;
            if (templatesBackedUp > 0)
            {
                templatesRemoved = RemoveFingerprintTemplatesFromDevice(deviceUserId);
                if (!templatesRemoved)
                {
                    _logger.LogWarning(
                        "Suspend {User}: templates backed up but removal unverified on device",
                        deviceUserId);
                }
            }

            if (!SetUserAccessOnDevice(deviceUserId, name, enabled: false))
                return Fail("SDK_ERROR", "Suspend failed");

            return Ok(new
            {
                suspended = true,
                appUserId = request.UserId,
                deviceUserId,
                templatesBackedUp,
                templatesRemoved
            });
        }
        finally
        {
            if (_state == DeviceConnectionState.Busy) _state = DeviceConnectionState.Online;
            _gate.Release();
        }
    }

    public async Task<ApiResponse> EnrollFingerprintAsync(EnrollRequest request, CancellationToken ct = default)
    {
        await _gate.WaitAsync(ct);
        try
        {
            var connect = await EnsureConnectedInternalAsync();
            if (!connect.Success)
                return Fail("DEVICE_OFFLINE", connect.Error ?? "Not connected", retryAfter: 30);

            _state = DeviceConnectionState.Busy;
            var deviceUserId = ResolveDeviceUserId(request.UserId);
            var name = request.Name ?? request.UserId;

            if (!VerifyUserOnDevice(deviceUserId, out _))
            {
                var create = CreateUserInternal(request.UserId, name, true);
                if (!create.Success) return create;
                deviceUserId = ResolveDeviceUserId(request.UserId);
            }

            var baselineHasTemplate = HasTemplate(deviceUserId, request.FingerIndex);

            _enrollTargetUserId = deviceUserId;
            _enrollFingerSucceeded = false;
            _enrollTcs = new TaskCompletionSource<EnrollFingerEventArgs>(
                TaskCreationOptions.RunContinuationsAsynchronously);

            // Clear stale enroll state from a prior session (e.g. probe or interrupted enroll).
            RunSdkSync("CancelOperation", new { deviceUserId }, () =>
            {
                _zk.CancelOperation();
                return true;
            });

            var startReturned = RunSdkSync("StartEnrollEx", new { deviceUserId, request.FingerIndex }, () =>
                _zk.StartEnrollEx(deviceUserId, request.FingerIndex, 1));

            LogSdkOnly("StartEnrollEx_return", new { startReturned }, startReturned);
            // Boolean return is NOT success — poll for SDK events and template changes.

            var timeout = TimeSpan.FromSeconds(Math.Clamp(request.TimeoutSec, 10, 60));
            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeoutCts.CancelAfter(timeout);

            var enrollVerified = false;
            try
            {
                while (!timeoutCts.Token.IsCancellationRequested)
                {
                    if (_enrollFingerSucceeded)
                    {
                        enrollVerified = true;
                        break;
                    }

                    if (_enrollTcs?.Task.IsCompletedSuccessfully == true)
                    {
                        var evt = _enrollTcs!.Task.Result;
                        if (IsEnrollEventSuccess(evt))
                        {
                            enrollVerified = true;
                            break;
                        }
                    }

                    if (HasTemplate(deviceUserId, request.FingerIndex) && !baselineHasTemplate)
                    {
                        enrollVerified = true;
                        break;
                    }

                    await Task.Delay(1500, timeoutCts.Token);
                }
            }
            catch (OperationCanceledException)
            {
                // timeout — final template check below
            }
            finally
            {
                _enrollTcs = null;
                _enrollTargetUserId = null;
            }

            if (!enrollVerified)
            {
                enrollVerified = _enrollFingerSucceeded
                    || (HasTemplate(deviceUserId, request.FingerIndex) && !baselineHasTemplate);
            }

            if (enrollVerified)
            {
                var mapping = _store.GetUser(request.UserId);
                if (mapping != null) mapping.FingerprintCount = Math.Max(mapping.FingerprintCount, 1);
                return new ApiResponse
                {
                    Success = true,
                    Verified = true,
                    EnrollState = EnrollStatus.Success.ToString().ToUpperInvariant(),
                    TemplateId = $"{request.UserId}_fp{request.FingerIndex}",
                    AppUserId = request.UserId,
                    DeviceUserId = deviceUserId,
                    RemoteModeStarted = startReturned
                };
            }

            if (startReturned)
            {
                return new ApiResponse
                {
                    Success = false,
                    Error = "Enrollment not verified — place finger on K50 or use device menu.",
                    ErrorCode = "PENDING",
                    EnrollState = EnrollStatus.Pending.ToString().ToUpperInvariant(),
                    RequiresOnDevice = true,
                    RemoteModeStarted = true,
                    AppUserId = request.UserId,
                    DeviceUserId = deviceUserId
                };
            }

            return Fail("ENROLL_UNSUPPORTED", "StartEnrollEx not accepted by device firmware", requiresOnDevice: true);
        }
        finally
        {
            if (_state == DeviceConnectionState.Busy) _state = DeviceConnectionState.Online;
            _gate.Release();
        }
    }

    public async Task<ApiResponse> VerifyFingerprintAsync(string userId, CancellationToken ct = default)
    {
        await _gate.WaitAsync(ct);
        try
        {
            var connect = await EnsureConnectedInternalAsync();
            if (!connect.Success)
                return Fail("DEVICE_OFFLINE", connect.Error ?? "Not connected");

            _state = DeviceConnectionState.Busy;
            var deviceUserId = ResolveDeviceUserId(userId);

            if (!VerifyUserOnDevice(deviceUserId, out _))
                return Fail("VERIFY_FAILED", "User not on device", requiresOnDevice: true);

            if (!HasAnyTemplate(deviceUserId) && !UserHasFingerprintHeuristic(deviceUserId))
                return Fail("VERIFY_FAILED", "No fingerprint template on device yet", requiresOnDevice: true);

            var mapping = _store.GetUser(userId);
            if (mapping != null) mapping.FingerprintCount = Math.Max(mapping.FingerprintCount, 1);

            return new ApiResponse
            {
                Success = true,
                Verified = true,
                TemplateId = $"{userId}_fp0",
                AppUserId = userId,
                DeviceUserId = deviceUserId
            };
        }
        finally
        {
            if (_state == DeviceConnectionState.Busy) _state = DeviceConnectionState.Online;
            _gate.Release();
        }
    }

    public async Task<int> SyncAttendanceAsync(CancellationToken ct = default)
    {
        await _gate.WaitAsync(ct);
        try
        {
            var connect = await EnsureConnectedInternalAsync();
            if (!connect.Success) return 0;

            _state = DeviceConnectionState.Busy;
            var inserted = 0;

            var readOk = RunSdkSync("ReadAllGLogData", null, () =>
                _zk.ReadAllGLogData(Options.MachineNumber));

            if (!readOk) return 0;

            string enrollNumber = "";
            int verifyMode = 0, inOutMode = 0, year = 0, month = 0, day = 0, hour = 0, minute = 0, second = 0;
            int workCode = 0;

            while (_zk.SSR_GetGeneralLogData(
                Options.MachineNumber,
                out enrollNumber,
                out verifyMode,
                out inOutMode,
                out year,
                out month,
                out day,
                out hour,
                out minute,
                out second,
                ref workCode))
            {
                var ts = new DateTime(year, month, day, hour, minute, second);
                if (TryRecordAndPushAttendance(enrollNumber, verifyMode, ts))
                    inserted++;
            }

            _lastPollAt = DateTime.UtcNow;
            LogSdkOnly("SyncAttendance", new { inserted }, inserted);
            return inserted;
        }
        finally
        {
            if (_state == DeviceConnectionState.Busy) _state = DeviceConnectionState.Online;
            _gate.Release();
        }
    }

    public Task<object> GetStatusAsync(CancellationToken ct = default)
    {
        ct.ThrowIfCancellationRequested();
        return Task.FromResult<object>(new
        {
            ok = _state == DeviceConnectionState.Online,
            state = _state.ToString().ToUpperInvariant(),
            ip = _ip,
            configuredIps = Options.AllDeviceIps,
            port = _port,
            lastError = _lastError,
            lastPollAt = _lastPollAt,
            storage = "in-memory (Flutter Drift + Supabase is source of truth)"
        });
    }

    private async Task<(bool Success, string? Error)> EnsureConnectedInternalAsync()
    {
        if (_state == DeviceConnectionState.Online) return (true, null);
        return await ConnectCoreAsync(_ip, _port);
    }

    private ApiResponse CreateUserInternal(string userId, string name, bool enabled)
    {
        var deviceUserId = MapToDeviceUserId(userId);
        var setOk = SetUserAccessOnDevice(deviceUserId, name, enabled);

        if (!setOk) return Fail("SDK_ERROR", "Create user failed");
        if (!VerifyUserOnDevice(deviceUserId, out _))
            return Fail("VERIFY_FAILED", "User not found after create");

        _store.UpsertUser(new UserMapping
        {
            AppUserId = userId,
            DeviceUserId = deviceUserId,
            Name = name,
            FingerprintCount = _store.GetUser(userId)?.FingerprintCount ?? 0
        });
        return Ok(new { created = true, deviceUserId });
    }

    private bool VerifyUserOnDevice(string deviceUserId, out string? name)
    {
        name = null;
        string resolvedName = "";
        var ok = RunSdkSync("SSR_GetUserInfo", new { deviceUserId }, () =>
        {
            var password = "";
            var privilege = 0;
            var enabled = false;
            return _zk.SSR_GetUserInfo(
                Options.MachineNumber,
                deviceUserId,
                out resolvedName,
                out password,
                out privilege,
                out enabled);
        });
        name = resolvedName;
        return ok;
    }

    private int CountTemplates(string deviceUserId, int fingerIndex)
    {
        var count = 0;
        for (var i = 0; i <= 9; i++)
        {
            if (HasTemplate(deviceUserId, i)) count++;
        }
        return count;
    }

    private bool HasTemplate(string deviceUserId, int fingerIndex)
    {
        return RunSdkSync("GetUserTmpExStr", new { deviceUserId, fingerIndex }, () =>
        {
            _zk.RefreshData(Options.MachineNumber);
            _zk.ReadAllTemplate(Options.MachineNumber);
            return _zk.GetUserTmpExStr(
                Options.MachineNumber,
                deviceUserId,
                fingerIndex,
                out _,
                out var tmpData,
                out var length) && length > 0;
        });
    }

    /// <summary>
    /// Fallback when GetUserTmpExStr rejects valid templates (some K50 firmware builds).
    /// </summary>
    private bool UserHasFingerprintHeuristic(string deviceUserId)
    {
        if (!int.TryParse(deviceUserId, out var enrollNumber)) return false;

        return RunSdkSync("GetUserTmpStr", new { deviceUserId }, () =>
        {
            _zk.RefreshData(Options.MachineNumber);
            _zk.ReadAllTemplate(Options.MachineNumber);
            for (var finger = 0; finger < 10; finger++)
            {
                var tmp = "";
                var length = 0;
                if (_zk.GetUserTmpStr(
                        Options.MachineNumber,
                        enrollNumber,
                        finger,
                        ref tmp,
                        ref length)
                    && length > 0)
                {
                    return true;
                }
            }

            return false;
        });
    }

    private bool HasAnyTemplate(string deviceUserId)
    {
        for (var i = 0; i < 10; i++)
        {
            if (HasTemplate(deviceUserId, i)) return true;
        }

        return UserHasFingerprintHeuristic(deviceUserId);
    }

    private bool TryReadTemplate(string deviceUserId, int fingerIndex, out int flag, out string tmpData)
    {
        flag = 0;
        tmpData = "";
        var length = 0;
        var readFlag = 0;
        var readTmp = "";
        var ok = RunSdkSync("GetUserTmpExStr_read", new { deviceUserId, fingerIndex }, () =>
        {
            _zk.RefreshData(Options.MachineNumber);
            _zk.ReadAllTemplate(Options.MachineNumber);
            return _zk.GetUserTmpExStr(
                Options.MachineNumber,
                deviceUserId,
                fingerIndex,
                out readFlag,
                out readTmp,
                out length) && length > 0 && !string.IsNullOrEmpty(readTmp);
        });
        if (ok)
        {
            flag = readFlag;
            tmpData = readTmp;
        }

        return ok;
    }

    /// <summary>Read templates from device and store in memory for restore on activate.</summary>
    private int BackupFingerprintTemplates(string deviceUserId, string appUserId)
    {
        var existing = _store.GetUser(appUserId);
        if (existing?.TemplateBackup is { Count: > 0 })
            return existing.TemplateBackup.Count;

        var backup = new Dictionary<int, FingerprintTemplateBackup>();
        for (var finger = 0; finger < 10; finger++)
        {
            if (TryReadTemplate(deviceUserId, finger, out var flag, out var data))
            {
                backup[finger] = new FingerprintTemplateBackup { Flag = flag, Data = data };
            }
        }

        if (backup.Count == 0)
            return 0;

        if (existing != null)
        {
            existing.TemplateBackup = backup;
        }
        else
        {
            _store.UpsertUser(new UserMapping
            {
                AppUserId = appUserId,
                DeviceUserId = deviceUserId,
                Name = appUserId,
                FingerprintCount = backup.Count,
                TemplateBackup = backup
            });
        }

        _logger.LogInformation(
            "Backed up {Count} fingerprint template(s) for user {User} before suspend",
            backup.Count,
            deviceUserId);
        return backup.Count;
    }

    private bool RemoveFingerprintTemplatesFromDevice(string deviceUserId)
    {
        for (var finger = 0; finger < 10; finger++)
        {
            if (!HasTemplate(deviceUserId, finger)) continue;

            RunSdkSync("SSR_DelUserTmp", new { deviceUserId, finger }, () =>
                _zk.SSR_DelUserTmp(Options.MachineNumber, deviceUserId, finger));
        }

        if (UserHasFingerprintHeuristic(deviceUserId))
        {
            for (var finger = 0; finger < 10; finger++)
            {
                RunSdkSync("SSR_DelUserTmp_force", new { deviceUserId, finger }, () =>
                    _zk.SSR_DelUserTmp(Options.MachineNumber, deviceUserId, finger));
            }
        }

        RunSdkSync("RefreshData_after_template_remove", new { deviceUserId }, () =>
        {
            _zk.RefreshData(Options.MachineNumber);
            return true;
        });

        return !HasAnyTemplate(deviceUserId);
    }

    private int RestoreFingerprintTemplates(string deviceUserId, string appUserId)
    {
        var mapping = _store.GetUser(appUserId);
        var backup = mapping?.TemplateBackup;
        if (backup == null || backup.Count == 0)
        {
            if (HasAnyTemplate(deviceUserId))
                return CountTemplates(deviceUserId, 0);

            _logger.LogWarning(
                "Activate {User}: no template backup in bridge memory — re-enroll fingerprint if needed",
                appUserId);
            return 0;
        }

        var restored = 0;
        foreach (var (finger, tpl) in backup)
        {
            var ok = RunSdkSync("SetUserTmpExStr", new { deviceUserId, finger, tpl.Flag }, () =>
                _zk.SetUserTmpExStr(
                    Options.MachineNumber,
                    deviceUserId,
                    finger,
                    tpl.Flag,
                    tpl.Data));
            if (ok) restored++;
        }

        RunSdkSync("RefreshData_after_template_restore", new { deviceUserId, restored }, () =>
        {
            _zk.RefreshData(Options.MachineNumber);
            return true;
        });

        if (restored > 0)
        {
            mapping!.TemplateBackup = null;
            mapping.FingerprintCount = Math.Max(mapping.FingerprintCount, restored);
            _logger.LogInformation(
                "Restored {Count} fingerprint template(s) for user {User}",
                restored,
                deviceUserId);
        }

        return restored;
    }

    private static bool IsEnrollEventSuccess(EnrollFingerEventArgs evt) =>
        evt.ActionResult == 0 || evt.TemplateLength > 0;

    private static string MapToDeviceUserId(string appUserId)
    {
        var trimmed = appUserId.Trim();
        if (trimmed.Length > 0 && trimmed.All(char.IsDigit))
            return trimmed;

        var digits = new string(trimmed.Where(char.IsDigit).ToArray());
        return digits.Length > 0 ? digits : trimmed;
    }

    /// <summary>Device password = numeric user ID (K50 PIN field).</summary>
    private static string DevicePassword(string deviceUserId) => deviceUserId;

    /// <summary>Normal member — not admin/manager (privilege 2 would still allow access).</summary>
    private const int NormalUserPrivilege = 0;

    private bool SetUserOnDevice(string deviceUserId, string name, int privilege, bool enabled) =>
        RunSdkSync("SSR_SetUserInfo", new { deviceUserId, name, privilege, enabled }, () =>
            _zk.SSR_SetUserInfo(
                Options.MachineNumber,
                deviceUserId,
                name,
                DevicePassword(deviceUserId),
                privilege,
                enabled));

    /// <summary>Enable or disable K50 user flags (templates managed separately on suspend/activate).</summary>
    private bool SetUserAccessOnDevice(string deviceUserId, string name, bool enabled)
    {
        if (!SetUserOnDevice(deviceUserId, name, NormalUserPrivilege, enabled))
            return false;

        RunSdkSync("SSR_EnableUser", new { deviceUserId, enabled }, () =>
            _zk.SSR_EnableUser(Options.MachineNumber, deviceUserId, enabled));

        if (!enabled)
            ApplyAccessValidityBlock(deviceUserId, block: true);
        else
            ApplyAccessValidityBlock(deviceUserId, block: false);

        RunSdkSync("RefreshData", new { deviceUserId, enabled }, () =>
        {
            _zk.RefreshData(Options.MachineNumber);
            return true;
        });

        if (TryReadUserEnabled(deviceUserId, out var onDeviceEnabled) && onDeviceEnabled != enabled)
        {
            _logger.LogWarning(
                "K50 user {User} SSR_GetUserInfo enabled={OnDevice}, requested={Requested}",
                deviceUserId, onDeviceEnabled, enabled);
        }

        return true;
    }

    /// <summary>Block access by validity window (works on firmware that ignores Enabled flag).</summary>
    private void ApplyAccessValidityBlock(string deviceUserId, bool block)
    {
        if (block)
        {
            var day = DateTime.Today.AddDays(-1).ToString("yyyy-MM-dd");
            RunSdkSync("SetUserValidDate_block", new { deviceUserId, day }, () =>
                _zk.SetUserValidDate(Options.MachineNumber, deviceUserId, 1, 0, day, day));
            return;
        }

        RunSdkSync("SetUserValidDate_clear", new { deviceUserId }, () =>
            _zk.SetUserValidDate(Options.MachineNumber, deviceUserId, 0, 0, "", ""));
    }

    private bool TryReadUserEnabled(string deviceUserId, out bool enabled)
    {
        enabled = true;
        var deviceName = "";
        var password = "";
        var privilege = 0;
        var readEnabled = false;
        var ok = RunSdkSync("SSR_GetUserInfo", new { deviceUserId }, () =>
            _zk.SSR_GetUserInfo(
                Options.MachineNumber,
                deviceUserId,
                out deviceName,
                out password,
                out privilege,
                out readEnabled));
        if (ok) enabled = readEnabled;
        return ok;
    }

    private string ResolveDeviceUserId(string appUserId) =>
        _store.GetUser(appUserId)?.DeviceUserId ?? MapToDeviceUserId(appUserId);

    private static bool UserIdsMatch(string? expected, string actual)
    {
        if (string.IsNullOrEmpty(expected) || string.IsNullOrWhiteSpace(actual)) return false;

        var expectedTrim = expected.Trim();
        var actualTrim = actual.Trim();
        if (string.Equals(expectedTrim, actualTrim, StringComparison.OrdinalIgnoreCase)) return true;

        var expectedMapped = MapToDeviceUserId(expectedTrim);
        var actualMapped = MapToDeviceUserId(actualTrim);
        if (string.Equals(expectedMapped, actualTrim, StringComparison.OrdinalIgnoreCase)) return true;
        if (string.Equals(expectedTrim, actualMapped, StringComparison.OrdinalIgnoreCase)) return true;
        if (string.Equals(expectedMapped, actualMapped, StringComparison.OrdinalIgnoreCase)) return true;

        // K50 often reports "17" while SSR user id is stored as "017".
        return NumericUserIdsEqual(expectedTrim, actualTrim)
            || NumericUserIdsEqual(expectedMapped, actualMapped)
            || NumericUserIdsEqual(expectedMapped, actualTrim)
            || NumericUserIdsEqual(expectedTrim, actualMapped);
    }

    private static bool NumericUserIdsEqual(string left, string right)
    {
        if (!long.TryParse(left, out var leftNum) || !long.TryParse(right, out var rightNum))
            return false;
        return leftNum == rightNum;
    }

    private async Task<(bool Success, string? Error)> RunSdkAsync(
        string method,
        object? parameters,
        Func<(bool Success, string? Error)> action,
        CancellationToken ct = default)
    {
        var sw = Stopwatch.StartNew();
        var before = _state.ToString();
        try
        {
            var result = await Task.Run(action, ct);
            _sdkLog.Log(new SdkCallLog
            {
                Method = method,
                Parameters = parameters,
                Result = result,
                DurationMs = sw.ElapsedMilliseconds,
                StateBefore = before,
                StateAfter = _state.ToString()
            });
            return result;
        }
        catch (Exception ex)
        {
            _lastError = ex.Message;
            _sdkLog.Log(new SdkCallLog
            {
                Method = method,
                Parameters = parameters,
                DurationMs = sw.ElapsedMilliseconds,
                StateBefore = before,
                StateAfter = _state.ToString(),
                Error = ex.Message
            });
            return (false, ex.Message);
        }
    }

    private bool RunSdkSync(string method, object? parameters, Func<bool> action)
    {
        var sw = Stopwatch.StartNew();
        var before = _state.ToString();
        try
        {
            var result = action();
            _sdkLog.Log(new SdkCallLog
            {
                Method = method,
                Parameters = parameters,
                Result = result,
                DurationMs = sw.ElapsedMilliseconds,
                StateBefore = before,
                StateAfter = _state.ToString()
            });
            return result;
        }
        catch (Exception ex)
        {
            _lastError = ex.Message;
            _sdkLog.Log(new SdkCallLog
            {
                Method = method,
                Parameters = parameters,
                DurationMs = sw.ElapsedMilliseconds,
                StateBefore = before,
                StateAfter = _state.ToString(),
                Error = ex.Message
            });
            return false;
        }
    }

    private void LogSdkOnly(string method, object? parameters, object? result)
    {
        _sdkLog.Log(new SdkCallLog
        {
            Method = method,
            Parameters = parameters,
            Result = result,
            DurationMs = 0,
            StateBefore = _state.ToString(),
            StateAfter = _state.ToString()
        });
    }

    private static ApiResponse Ok(object extra) => new() { Success = true, Verified = true, Extra = ObjectToDict(extra) };

    private static ApiResponse Fail(string code, string message, bool requiresOnDevice = false, int? retryAfter = null) =>
        new()
        {
            Success = false,
            Error = message,
            ErrorCode = code,
            RequiresOnDevice = requiresOnDevice,
            RetryAfter = retryAfter,
            EnrollState = EnrollStatus.Failed.ToString().ToUpperInvariant()
        };

    private static Dictionary<string, object?> ObjectToDict(object obj)
    {
        var dict = new Dictionary<string, object?>();
        foreach (var prop in obj.GetType().GetProperties())
            dict[prop.Name] = prop.GetValue(obj);
        return dict;
    }

    public void Dispose()
    {
        try { _zk.Disconnect(); } catch { /* ignore */ }
    }

    private sealed record EnrollFingerEventArgs(
        string UserId,
        int FingerIndex,
        int ActionResult,
        int TemplateLength,
        bool IsEx);
}
