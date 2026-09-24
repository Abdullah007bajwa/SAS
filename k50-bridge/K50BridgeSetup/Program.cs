using System.Diagnostics;
using System.Net.Http;
using Microsoft.Win32;

namespace K50BridgeSetup;

internal static class Program
{
    private const string TaskName = "MasterGym-K50Bridge";
    private static readonly string Clsid = "{00853A19-BD51-419B-9269-2DABE57EB61F}";

    [STAThread]
    private static int Main()
    {
        ApplicationConfiguration.Initialize();

        var installDir = AppContext.BaseDirectory.TrimEnd('\\');
        var exe = Path.Combine(installDir, "K50Bridge.exe");
        var sdkX86 = Path.Combine(installDir, "sdk", "x86");

        if (!File.Exists(exe))
        {
            ShowError($"K50Bridge.exe not found in:\n{installDir}\n\nExtract the full package before running Install.exe.");
            return 1;
        }

        if (!File.Exists(Path.Combine(sdkX86, "zkemkeeper.dll")))
        {
            ShowError($"ZKTeco SDK missing:\n{sdkX86}\\zkemkeeper.dll");
            return 1;
        }

        try
        {
            InstallSdkCom(sdkX86);
            RegisterStartupTask(exe, installDir);
            StartBridge(exe, installDir);

            if (!WaitForHealth(TimeSpan.FromSeconds(45)))
            {
                ShowError(
                    "K50Bridge started but did not respond on port 8787.\n\n" +
                    "Check Windows Firewall and run K50Bridge.exe manually to see errors.");
                return 1;
            }

            MessageBox.Show(
                "Master City Gym — K50 Bridge installed.\n\n" +
                $"Folder: {installDir}\n" +
                "Runs automatically on every startup.\n\n" +
                "Edit appsettings.json to set the K50 device IP.\n" +
                "Test: http://127.0.0.1:8787/device/status",
                "K50 Bridge",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
            return 0;
        }
        catch (Exception ex)
        {
            ShowError(ex.Message);
            return 1;
        }
    }

    private static void InstallSdkCom(string sdkX86)
    {
        var sysWow = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "SysWOW64");
        foreach (var dll in Directory.GetFiles(sdkX86, "*.dll"))
        {
            File.Copy(dll, Path.Combine(sysWow, Path.GetFileName(dll)), overwrite: true);
        }

        var regsvr = Path.Combine(sysWow, "regsvr32.exe");
        var zk = Path.Combine(sysWow, "zkemkeeper.dll");
        RunHidden(regsvr, $"/s \"{zk}\"");

        if (!IsComRegistered())
            throw new InvalidOperationException("ZKTeco COM registration failed. Run as Administrator.");
    }

    private static bool IsComRegistered()
    {
        var paths = new[]
        {
            $@"SOFTWARE\WOW6432Node\Classes\CLSID\{Clsid}\InprocServer32",
            $@"CLSID\{Clsid}\InprocServer32"
        };

        foreach (var path in paths)
        {
            using var key = Registry.LocalMachine.OpenSubKey(path) ?? Registry.ClassesRoot.OpenSubKey(path);
            if (key != null) return true;
        }

        return false;
    }

    private static void RegisterStartupTask(string exe, string workDir)
    {
        var xmlPath = Path.Combine(Path.GetTempPath(), "MasterGym-K50Bridge.xml");
        File.WriteAllText(xmlPath, $"""
            <?xml version="1.0" encoding="UTF-16"?>
            <Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
              <Triggers>
                <BootTrigger>
                  <Delay>PT30S</Delay>
                  <Enabled>true</Enabled>
                </BootTrigger>
                <LogonTrigger>
                  <Enabled>true</Enabled>
                </LogonTrigger>
              </Triggers>
              <Actions Context="Author">
                <Exec>
                  <Command>"{exe}"</Command>
                  <WorkingDirectory>"{workDir}"</WorkingDirectory>
                </Exec>
              </Actions>
              <Settings>
                <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
                <RestartOnFailure>
                  <Interval>PT1M</Interval>
                  <Count>3</Count>
                </RestartOnFailure>
                <StartWhenAvailable>true</StartWhenAvailable>
                <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
              </Settings>
              <Principals>
                <Principal id="Author">
                  <RunLevel>HighestAvailable</RunLevel>
                </Principal>
              </Principals>
            </Task>
            """);

        RunHidden("schtasks.exe", $"/Create /TN \"{TaskName}\" /XML \"{xmlPath}\" /F");
        try { File.Delete(xmlPath); } catch { /* ignore */ }
    }

    private static void StartBridge(string exe, string workDir)
    {
        foreach (var proc in Process.GetProcessesByName("K50Bridge"))
        {
            try { proc.Kill(entireProcessTree: true); } catch { /* ignore */ }
        }

        Process.Start(new ProcessStartInfo
        {
            FileName = exe,
            WorkingDirectory = workDir,
            UseShellExecute = true
        });
    }

    private static bool WaitForHealth(TimeSpan timeout)
    {
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(3) };
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            try
            {
                var response = http.GetAsync("http://127.0.0.1:8787/health").GetAwaiter().GetResult();
                if (response.IsSuccessStatusCode) return true;
            }
            catch
            {
                /* bridge still starting */
            }

            Thread.Sleep(1000);
        }

        return false;
    }

    private static void RunHidden(string fileName, string arguments)
    {
        using var proc = Process.Start(new ProcessStartInfo
        {
            FileName = fileName,
            Arguments = arguments,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        }) ?? throw new InvalidOperationException($"Failed to start {fileName}");

        proc.WaitForExit();
        if (proc.ExitCode != 0)
        {
            var err = proc.StandardError.ReadToEnd();
            throw new InvalidOperationException($"{fileName} failed ({proc.ExitCode}): {err}".Trim());
        }
    }

    private static void ShowError(string message) =>
        MessageBox.Show(message, "K50 Bridge Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
}
