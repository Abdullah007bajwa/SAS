using K50Bridge.Configuration;
using zkemkeeper;

namespace K50Bridge.Services;

/// <summary>
/// Ordered SDK connectivity test — run before trusting enrollment APIs.
/// Step 1: Connect_Net → Step 2: device query → Step 3: StartEnrollEx + verify.
/// </summary>
public static class ConnectivityProbe
{
    public static int Run(string ip, int port, int machineNumber = 1, string enrollUserId = "1001", int commPassword = 0)
    {
        Console.WriteLine("=== K50 SDK Connectivity Probe (official zkemkeeper) ===");
        Console.WriteLine($"Target: {ip}:{port}  machine={machineNumber}  enrollUser={enrollUserId}");
        Console.WriteLine();

        var zk = new CZKEMClass();
        var enrollEventReceived = false;
        var enrollEventDetail = "";

        void OnEnrollFingerEx(string enrollNumber, int fingerIndex, int actionResult, int templateLength)
        {
            enrollEventReceived = true;
            enrollEventDetail =
                $"OnEnrollFingerEx user={enrollNumber} finger={fingerIndex} result={actionResult} len={templateLength}";
            Console.WriteLine($"  [EVENT] {enrollEventDetail}");
        }

        void OnEnrollFinger(int enrollNumber, int fingerIndex, int actionResult, int templateLength)
        {
            enrollEventReceived = true;
            enrollEventDetail =
                $"OnEnrollFinger uid={enrollNumber} finger={fingerIndex} result={actionResult} len={templateLength}";
            Console.WriteLine($"  [EVENT] {enrollEventDetail}");
        }

        zk.OnEnrollFingerEx += OnEnrollFingerEx;
        zk.OnEnrollFinger += OnEnrollFinger;

        try
        {
            // ── Step 1: Connect (DO NOT SKIP) ─────────────────────────────────
            Console.WriteLine("Step 1: Connect_Net");
            ZkSdkHelper.ApplyCommPassword(zk, commPassword);
            if (commPassword != 0)
                Console.WriteLine($"  SetCommPassword({commPassword})");

            var connectOk = zk.Connect_Net(ip, port);
            Console.WriteLine($"  Connect_Net(\"{ip}\", {port}) => {connectOk}");

            if (!connectOk)
            {
                var err = ZkSdkHelper.GetLastError(zk);
                if (err > 0)
                    Console.WriteLine($"  GetLastError => {err}");
            }

            if (!connectOk)
            {
                Console.WriteLine();
                Console.WriteLine("FAIL: Connect_Net returned false.");
                Console.WriteLine("  TCP can succeed while SDK fails — usual fixes:");
                Console.WriteLine("  1. Admin: run .\\setup-sdk.ps1 (copies SDK DLLs to SysWOW64 + regsvr32)");
                Console.WriteLine("  2. Close ZKTime/ZKBio/Flutter and stop run-api.ps1 (one client only)");
                Console.WriteLine("  3. If device has Comm Key: set K50:CommPassword in appsettings.json");
                Console.WriteLine("  4. Reboot K50 after changing network settings");
                return 1;
            }

            Console.WriteLine("  OK: Device reachable via SDK.");
            Console.WriteLine();

            // ── Step 2: Basic device communication ────────────────────────────
            Console.WriteLine("Step 2: Verify device communication");

            var regOk = zk.RegEvent(machineNumber, 65535);
            Console.WriteLine($"  RegEvent({machineNumber}, 65535) => {regOk}");

            var statusValue = 0;
            var statusOk = zk.GetDeviceStatus(machineNumber, 1, ref statusValue);
            Console.WriteLine($"  GetDeviceStatus({machineNumber}, 1, out value) => {statusOk}, value={statusValue}");

            var serialOk = zk.GetSerialNumber(machineNumber, out var serialNumber);
            if (serialOk)
                Console.WriteLine($"  GetSerialNumber => {serialNumber}");

            var userCount = 0;
            if (zk.ReadAllUserID(machineNumber))
            {
                var enroll = "";
                var name = "";
                var password = "";
                var privilege = 0;
                var enabled = false;
                while (zk.SSR_GetAllUserInfo(
                    machineNumber,
                    out enroll,
                    out name,
                    out password,
                    out privilege,
                    out enabled))
                {
                    userCount++;
                }
            }

            Console.WriteLine($"  User count on device: {userCount}");
            Console.WriteLine("  OK: SDK queries completed.");
            Console.WriteLine();

            // Ensure test user exists before enroll
            Console.WriteLine("  Ensuring test user on device (SSR_SetUserInfo)...");
            var setUserOk = zk.SSR_SetUserInfo(
                machineNumber,
                enrollUserId,
                $"Probe {enrollUserId}",
                enrollUserId,
                0,
                true);
            Console.WriteLine($"  SSR_SetUserInfo(\"{enrollUserId}\") => {setUserOk}");

            var templateBefore = HasTemplate(zk, machineNumber, enrollUserId, 0);
            Console.WriteLine($"  Template finger 0 before enroll: {(templateBefore ? "exists" : "none")}");
            Console.WriteLine();

            // ── Step 3: Enrollment capability (critical) ────────────────────
            Console.WriteLine("Step 3: StartEnrollEx (watch K50 screen NOW)");
            Console.WriteLine("  Expected Case A: screen shows \"Place Finger\" / User ID");
            Console.WriteLine();

            var startResult = zk.StartEnrollEx(enrollUserId, 0, 1);
            Console.WriteLine($"  StartEnrollEx(\"{enrollUserId}\", 0, 1) => {startResult}");
            Console.WriteLine("  >>> PLACE FINGER ON K50 NOW (polling up to 45s) <<<");

            var templateAfter = templateBefore;
            for (var elapsed = 0; elapsed < 45; elapsed += 3)
            {
                Thread.Sleep(3000);
                templateAfter = HasTemplate(zk, machineNumber, enrollUserId, 0);
                if (enrollEventReceived || (templateAfter && !templateBefore))
                {
                    Console.WriteLine($"  Detected enrollment activity at {elapsed + 3}s");
                    break;
                }

                Console.WriteLine($"  ... {elapsed + 3}s — event={enrollEventReceived}, template={(templateAfter ? "exists" : "none")}");
            }

            if (!templateAfter)
                templateAfter = HasTemplate(zk, machineNumber, enrollUserId, 0);
            Console.WriteLine($"  Template finger 0 after wait: {(templateAfter ? "exists" : "none")}");

            Console.WriteLine();
            Console.WriteLine("=== Result ===");

            if (enrollEventReceived || (templateAfter && !templateBefore))
            {
                Console.WriteLine("Case A — VERIFIED enrollment activity:");
                if (enrollEventReceived) Console.WriteLine($"  Event: {enrollEventDetail}");
                if (templateAfter && !templateBefore) Console.WriteLine("  New fingerprint template detected on device.");
                Console.WriteLine("  Level 2 remote enrollment is supported (with event/template verification).");
                return 0;
            }

            if (startResult)
            {
                Console.WriteLine("Case B — StartEnrollEx accepted BUT not verified in 45s:");
                Console.WriteLine("  No OnEnrollFinger event and no new template detected.");
                Console.WriteLine("  If K50 showed enroll UI, scan finger during the wait window.");
                Console.WriteLine("  App can still Confirm after manual/device-menu enrollment.");
                return 2;
            }

            Console.WriteLine("Case C — StartEnrollEx returned false / not accepted.");
            Console.WriteLine("  Device not ready or feature not supported on this firmware.");
            return 3;
        }
        catch (Exception ex)
        {
            Console.WriteLine();
            Console.WriteLine($"ERROR: {ex.Message}");
            Console.WriteLine(ex.StackTrace);
            return 99;
        }
        finally
        {
            try { zk.Disconnect(); } catch { /* ignore */ }
        }
    }

    private static bool HasTemplate(CZKEMClass zk, int machineNumber, string userId, int fingerIndex)
    {
        try
        {
            return zk.GetUserTmpExStr(machineNumber, userId, fingerIndex, out _, out var tmpData, out var length)
                && length > 0
                && !string.IsNullOrEmpty(tmpData);
        }
        catch
        {
            return false;
        }
    }

    public static (string Ip, int Port, int Machine, string EnrollUser) ParseArgs(string[] args, K50Options defaults)
    {
        var ip = defaults.DeviceIp;
        var port = defaults.DevicePort;
        var machine = defaults.MachineNumber;
        var enrollUser = "1001";

        for (var i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--ip" when i + 1 < args.Length:
                    ip = args[++i];
                    break;
                case "--port" when i + 1 < args.Length:
                    port = int.Parse(args[++i]);
                    break;
                case "--machine" when i + 1 < args.Length:
                    machine = int.Parse(args[++i]);
                    break;
                case "--user" when i + 1 < args.Length:
                    enrollUser = args[++i];
                    break;
            }
        }

        return (ip, port, machine, enrollUser);
    }
}
