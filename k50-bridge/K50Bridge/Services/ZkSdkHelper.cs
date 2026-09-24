using zkemkeeper;

namespace K50Bridge.Services;

internal static class ZkSdkHelper
{
    public static int GetLastError(CZKEMClass zk)
    {
        var code = 0;
        try
        {
            zk.GetLastError(ref code);
        }
        catch
        {
            // ignore
        }

        return code;
    }

    public static string DescribeConnectFailure(CZKEMClass zk, bool connectOk)
    {
        if (connectOk) return "connected";

        var err = GetLastError(zk);
        return err > 0
            ? $"Connect_Net returned false (SDK error {err})"
            : "Connect_Net returned false (no SDK error code — check COM registration and dependent DLLs in SysWOW64)";
    }

    public static void ApplyCommPassword(CZKEMClass zk, int commPassword)
    {
        if (commPassword == 0) return;
        zk.SetCommPassword(commPassword);
    }

    public static bool TryConnect(CZKEMClass zk, string ip, int port, int commPassword, out string? error)
    {
        ApplyCommPassword(zk, commPassword);
        var ok = zk.Connect_Net(ip, port);
        if (ok)
        {
            error = null;
            return true;
        }

        error = DescribeConnectFailure(zk, false);
        return false;
    }
}
