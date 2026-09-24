using K50Bridge.Configuration;
using K50Bridge.Logging;
using K50Bridge.Services;
using K50Bridge.Storage;
using Microsoft.Extensions.Configuration;

static string ResolveLogDirectory(int apiPort)
{
    var folder = apiPort == 8788 ? "K50Bridge2" : "K50Bridge";
    var logDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
        "Master City Gym",
        folder,
        "logs");
    Directory.CreateDirectory(logDir);
    return logDir;
}

// Probe mode: dotnet run -- --probe [--ip 192.168.1.201] [--port 4370] [--user 1001]
if (args.Contains("--probe"))
{
    var config = new ConfigurationBuilder()
        .SetBasePath(AppContext.BaseDirectory)
        .AddJsonFile("appsettings.json", optional: true)
        .AddJsonFile("appsettings.Development.json", optional: true)
        .AddEnvironmentVariables()
        .Build();

    var defaults = config.GetSection(K50Options.SectionName).Get<K50Options>() ?? new K50Options();
    var (ip, port, machine, enrollUser) = ConnectivityProbe.ParseArgs(args, defaults);
    Environment.Exit(ConnectivityProbe.Run(ip, port, machine, enrollUser, defaults.CommPassword));
}

var preConfig = new ConfigurationBuilder()
    .SetBasePath(AppContext.BaseDirectory)
    .AddJsonFile("appsettings.json", optional: true)
    .AddEnvironmentVariables()
    .Build();
var k50Preview = preConfig.GetSection(K50Options.SectionName).Get<K50Options>() ?? new K50Options();
var logDir = ResolveLogDirectory(k50Preview.ApiPort);

var builder = WebApplication.CreateBuilder(new WebApplicationOptions
{
    Args = args,
    ContentRootPath = AppContext.BaseDirectory,
});

builder.Logging.AddProvider(new FileLoggerProvider(Path.Combine(logDir, "k50bridge.log")));

builder.Services.Configure<K50Options>(builder.Configuration.GetSection(K50Options.SectionName));
var k50ForStore = builder.Configuration.GetSection(K50Options.SectionName).Get<K50Options>() ?? new K50Options();
builder.Services.AddSingleton(_ => new BridgeMemoryStore(k50ForStore.ApiPort));
builder.Services.AddSingleton<ISdkLogger, SdkLogger>();
builder.Services.AddSingleton<AttendancePushBroadcaster>();
builder.Services.AddSingleton<IDeviceManager, DeviceManager>();
builder.Services.AddHostedService<AttendancePollingService>();
builder.Services.AddControllers();
builder.Services.AddCors(o => o.AddDefaultPolicy(p =>
    p.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod()));

var k50 = builder.Configuration.GetSection(K50Options.SectionName).Get<K50Options>() ?? new K50Options();
builder.WebHost.UseUrls($"http://0.0.0.0:{k50.ApiPort}");

var app = builder.Build();

app.UseWebSockets(new WebSocketOptions
{
    KeepAliveInterval = TimeSpan.FromSeconds(30),
});
app.UseCors();
app.MapControllers();
app.Map("/device/attendance/ws", async (
    HttpContext context,
    AttendancePushBroadcaster broadcaster) =>
{
    if (!context.WebSockets.IsWebSocketRequest)
    {
        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        await context.Response.WriteAsync("WebSocket connection required");
        return;
    }

    var socket = await context.WebSockets.AcceptWebSocketAsync();
    await broadcaster.HandleWebSocketAsync(socket, context.RequestAborted);
});

app.Logger.LogInformation(
    "K50 Bridge starting on port {Port} — device IPs: {Ips} — logs: {LogDir}",
    k50.ApiPort,
    string.Join(", ", k50.AllDeviceIps),
    logDir);
app.Run();
