using K50Bridge.Models;
using Microsoft.AspNetCore.Mvc;

namespace K50Bridge.Extensions;

public static class ApiResponseExtensions
{
    public static object ToPayload(this ApiResponse r)
    {
        var dict = new Dictionary<string, object?>
        {
            ["success"] = r.Success,
            ["error"] = r.Error,
            ["errorCode"] = r.ErrorCode,
            ["retryAfter"] = r.RetryAfter,
            ["enrollState"] = r.EnrollState,
            ["requiresOnDevice"] = r.RequiresOnDevice,
            ["remoteModeStarted"] = r.RemoteModeStarted,
            ["templateId"] = r.TemplateId,
            ["deviceUserId"] = r.DeviceUserId,
            ["appUserId"] = r.AppUserId,
            ["verified"] = r.Verified
        };

        foreach (var kv in r.Extra)
            dict[kv.Key] = kv.Value;

        return dict;
    }

    public static IActionResult ToResult(this ApiResponse r, HttpContext ctx)
    {
        var status = r.Success ? StatusCodes.Status200OK
            : r.ErrorCode == "DEVICE_OFFLINE" ? StatusCodes.Status503ServiceUnavailable
            : r.ErrorCode == "PENDING" ? StatusCodes.Status200OK
            : StatusCodes.Status422UnprocessableEntity;

        return new JsonResult(r.ToPayload()) { StatusCode = status };
    }
}
