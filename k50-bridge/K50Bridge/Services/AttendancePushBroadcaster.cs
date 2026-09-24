using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using K50Bridge.Models;

namespace K50Bridge.Services;

/// <summary>
/// Pushes new attendance records to connected Flutter clients over WebSocket.
/// Polling remains the backup path when push is missed.
/// </summary>
public sealed class AttendancePushBroadcaster
{
    private readonly ConcurrentDictionary<Guid, WebSocket> _clients = new();
    private readonly ILogger<AttendancePushBroadcaster> _logger;

    public AttendancePushBroadcaster(ILogger<AttendancePushBroadcaster> logger)
    {
        _logger = logger;
    }

    public async Task HandleWebSocketAsync(WebSocket webSocket, CancellationToken ct)
    {
        var id = Guid.NewGuid();
        _clients[id] = webSocket;
        _logger.LogInformation("Attendance WebSocket client connected ({Count} total)", _clients.Count);

        var buffer = new byte[256];
        try
        {
            while (webSocket.State == WebSocketState.Open && !ct.IsCancellationRequested)
            {
                var result = await webSocket.ReceiveAsync(buffer, ct);
                if (result.MessageType == WebSocketMessageType.Close)
                    break;
            }
        }
        catch (OperationCanceledException)
        {
            // App shutting down.
        }
        catch (WebSocketException ex)
        {
            _logger.LogDebug(ex, "Attendance WebSocket receive ended");
        }
        finally
        {
            _clients.TryRemove(id, out _);
            if (webSocket.State == WebSocketState.Open ||
                webSocket.State == WebSocketState.CloseReceived)
            {
                try
                {
                    await webSocket.CloseAsync(
                        WebSocketCloseStatus.NormalClosure,
                        "closing",
                        CancellationToken.None);
                }
                catch
                {
                    // Client already gone.
                }
            }

            _logger.LogInformation(
                "Attendance WebSocket client disconnected ({Count} remaining)",
                _clients.Count);
        }
    }

    public void Broadcast(AttendanceRecord record)
    {
        if (_clients.IsEmpty) return;

        var payload = JsonSerializer.Serialize(new
        {
            type = "attendance",
            log = new
            {
                userId = record.UserId,
                deviceUserId = record.DeviceUserId,
                timestamp = record.Timestamp.ToUniversalTime().ToString("o"),
                verifyType = record.VerifyType
            }
        });
        var bytes = Encoding.UTF8.GetBytes(payload);
        var segment = new ArraySegment<byte>(bytes);

        foreach (var (id, socket) in _clients)
        {
            if (socket.State != WebSocketState.Open)
            {
                _clients.TryRemove(id, out _);
                continue;
            }

            try
            {
                _ = socket.SendAsync(segment, WebSocketMessageType.Text, true, CancellationToken.None);
            }
            catch (Exception ex)
            {
                _clients.TryRemove(id, out _);
                _logger.LogDebug(ex, "Attendance WebSocket send failed; client removed");
            }
        }
    }
}
