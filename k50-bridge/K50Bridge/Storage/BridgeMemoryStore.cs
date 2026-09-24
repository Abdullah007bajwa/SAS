using System.Collections.Concurrent;
using System.Text.Json;
using K50Bridge.Models;

namespace K50Bridge.Storage;

/// <summary>
/// Bridge buffer with persisted user ID mappings (app code ↔ device ID).
/// Flutter Drift + Supabase remain the system of record for attendance.
/// </summary>
public sealed class BridgeMemoryStore
{
    private readonly ConcurrentDictionary<string, UserMapping> _users = new();
    private readonly ConcurrentDictionary<string, byte> _attendanceKeys = new();
    private readonly List<AttendanceRecord> _attendance = new();
    private readonly object _attendanceLock = new();
    private readonly string _mappingPath;
    private const int MaxAttendance = 5000;

    public BridgeMemoryStore(int apiPort)
    {
        var folder = apiPort == 8788 ? "K50Bridge2" : "K50Bridge";
        var root = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "School Attendance Portal",
            folder);
        Directory.CreateDirectory(root);
        _mappingPath = Path.Combine(root, "user-mappings.json");
        LoadMappings();
    }

    public void UpsertUser(UserMapping mapping)
    {
        _users[mapping.AppUserId] = mapping;
        SaveMappings();
    }

    public UserMapping? GetUser(string appUserId) =>
        _users.TryGetValue(appUserId, out var m) ? m : null;

    public UserMapping? GetUserByDeviceId(string deviceUserId)
    {
        foreach (var mapping in _users.Values)
        {
            if (string.Equals(mapping.DeviceUserId, deviceUserId, StringComparison.OrdinalIgnoreCase))
                return mapping;
        }

        return null;
    }

    public void RemoveUser(string appUserId)
    {
        if (_users.TryRemove(appUserId, out _))
            SaveMappings();
    }

    public IReadOnlyList<UserMapping> ListUsers() => _users.Values.ToList();

    public bool AddAttendance(AttendanceRecord record)
    {
        var key = $"{record.DeviceUserId}:{record.Timestamp:O}";
        if (!_attendanceKeys.TryAdd(key, 0)) return false;

        lock (_attendanceLock)
        {
            _attendance.Add(record);
            while (_attendance.Count > MaxAttendance)
            {
                var removed = _attendance[0];
                _attendance.RemoveAt(0);
                _attendanceKeys.TryRemove($"{removed.DeviceUserId}:{removed.Timestamp:O}", out _);
            }
        }

        return true;
    }

    public IReadOnlyList<AttendanceRecord> GetAttendance(DateTime? since, int limit = 200)
    {
        lock (_attendanceLock)
        {
            IEnumerable<AttendanceRecord> q = _attendance;
            if (since.HasValue)
                q = q.Where(a => a.Timestamp > since.Value);
            return q.OrderBy(a => a.Timestamp).TakeLast(limit).ToList();
        }
    }

    private void LoadMappings()
    {
        if (!File.Exists(_mappingPath)) return;

        try
        {
            var json = File.ReadAllText(_mappingPath);
            var list = JsonSerializer.Deserialize<List<UserMapping>>(json);
            if (list == null) return;

            foreach (var mapping in list)
            {
                if (string.IsNullOrWhiteSpace(mapping.AppUserId)) continue;
                _users[mapping.AppUserId] = mapping;
            }
        }
        catch
        {
            // Corrupt file — start fresh; mappings rebuild on next enroll/sync.
        }
    }

    private void SaveMappings()
    {
        try
        {
            var list = _users.Values.ToList();
            var json = JsonSerializer.Serialize(list, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(_mappingPath, json);
        }
        catch
        {
            // Non-fatal — in-memory mapping still works until restart.
        }
    }
}
