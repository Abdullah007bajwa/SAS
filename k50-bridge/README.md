# K50 Bridge — Official ZKTeco SDK (ASP.NET Core x86)

Windows-only HTTP bridge between the Flutter app and ZKTeco K50 using **official zkemkeeper COM SDK** (Standalone SDK 6.3.1.55).

```
Flutter  →  HTTP :8787  →  K50Bridge (x86)  →  COM zkemkeeper  →  K50 :4370
```

Persistent data stays in **Flutter Drift (SQLite) + Supabase**. This service only controls the device and buffers recent attendance in memory.

---

## Prerequisites

1. **ZKTeco Standalone SDK** installed at `C:\ZKTecoSDK` (do not copy into this repo)
2. **Windows x86** — zkemkeeper is 32-bit COM
3. **.NET 8 SDK** (x86 build)

---

## 1. Register COM + generate Interop (one time)

**PowerShell as Administrator** from `k50-bridge`:

```powershell
cd E:\GYM\Master-gym\k50-bridge
.\setup-sdk.ps1
```

This runs `regsvr32` on `C:\ZKTecoSDK\sdk\x86\zkemkeeper.dll` and generates `K50Bridge\lib\Interop.zkemkeeper.dll` via `TlbImp.exe` (required — `dotnet build` cannot use COMReference).

Manual alternative:

```cmd
C:\Windows\SysWOW64\regsvr32.exe "C:\ZKTecoSDK\sdk\x86\zkemkeeper.dll"
"C:\Program Files (x86)\Microsoft SDKs\Windows\v10.0A\bin\NETFX 4.8 Tools\TlbImp.exe" "C:\ZKTecoSDK\sdk\x86\zkemkeeper.dll" /out:K50Bridge\lib\Interop.zkemkeeper.dll /namespace:zkemkeeper
```

Verify CLSID registration:

```cmd
reg query HKCR\CLSID\{00853A19-BD51-419B-9269-2DABE57EB61F}\InprocServer32
```

---

## 2. Configure device IP

Edit `K50Bridge/appsettings.json`:

```json
"K50": {
  "DeviceIp": "192.168.100.18",
  "DevicePort": 4370,
  "ApiPort": 8787
}
```

If build fails with **Interop.zkemkeeper not found**, run `.\setup-sdk.ps1` (see step 1).

Build with explicit SDK path if needed:

```cmd
dotnet build K50Bridge\K50Bridge.csproj -p:ZKTecoSdkPath=C:\ZKTecoSDK -p:Platform=x86
```

---

## 3. Build x86 (Visual Studio)

1. Open `K50Bridge.sln`
2. **Configuration Manager** → Platform **x86** (not Any CPU)
3. Build → Release | x86

Or CLI:

```cmd
cd k50-bridge
dotnet build K50Bridge.sln -c Release -p:Platform=x86
```

---

## 4. Run

All commands below assume you are in the **`k50-bridge`** folder (repo root is `Master-gym/k50-bridge`).

### First connectivity test (DO THIS BEFORE THE API)

**PowerShell (easiest):**

```powershell
cd E:\GYM\Master-gym\k50-bridge
.\run-probe.ps1 -Ip 192.168.100.18 -Port 4370 -User 1001
```

**Or dotnet directly** — the `.csproj` lives in `K50Bridge\`, not the folder root:

```powershell
cd E:\GYM\Master-gym\k50-bridge
dotnet run --project K50Bridge\K50Bridge.csproj -c Release -p:Platform=x86 -- --probe --ip 192.168.100.18 --port 4370 --user 1001
```

> If you see `Couldn't find a project to run`, you ran `dotnet run` from `k50-bridge` without `--project K50Bridge\K50Bridge.csproj`. Use `.\run-probe.ps1` instead.

**Watch the K50 screen during step 3.**

| Exit code | Meaning |
|-----------|---------|
| 0 | Case A — event or new template verified (Level 2 supported) |
| 1 | Connect_Net false — network/IP issue |
| 2 | Case B — StartEnrollEx true but no event/template (ACK only) |
| 3 | Case C — StartEnrollEx false / not supported |

Service listens on `http://0.0.0.0:8787` when run without `--probe`:

```powershell
.\run-api.ps1
```

Or:

```cmd
dotnet run --project K50Bridge -c Release -p:Platform=x86
```

Test:

```cmd
curl http://127.0.0.1:8787/device/status
curl -X POST http://127.0.0.1:8787/device/connect -H "Content-Type: application/json" -d "{}"
```

---

## 5. Flutter app

1. Settings → **Simulation OFF**
2. **K50 Bridge URL** → `http://127.0.0.1:8787`
3. Save

---

## API endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/device/connect` | `Connect_Net` + `RegEvent(65535)` |
| GET | `/device/status` | Device/bridge state |
| GET | `/health` | Alias for status |
| POST | `/device/user/create` | `SSR_SetUserInfo` + verify |
| POST | `/device/user/delete` | Delete user on device |
| POST | `/device/user/enable` | Enable user |
| POST | `/device/user/suspend` | Disable user |
| POST | `/device/fingerprint/enroll` | `StartEnrollEx` + `OnEnrollFinger` / template verify |
| POST | `/device/fingerprint/verify` | Confirm template exists |
| GET | `/device/attendance` | In-memory attendance buffer (poll) |
| GET | `/device/attendance/sync` | Same as `/device/attendance` |
| WS | `/device/attendance/ws` | Real-time push when a new scan is recorded |

Attendance uses **push + poll**: `OnAttTransaction` / `OnAttTransactionEx` push new scans to connected Flutter clients; `AttendancePollingService` and `GET /device/attendance` remain the backup path.

---

## Enrollment rules (production)

- `StartEnrollEx` **boolean return is NOT success**
- Success requires `OnEnrollFinger` / `OnEnrollFingerEx` **or** template count increase via `GetUserTmpExStr`
- Returns `PENDING` + `requiresOnDevice: true` when enroll mode started but not verified within timeout

---

## SDK methods used

- `Connect_Net` / `Disconnect`
- `RegEvent(1, 65535)`
- `OnAttTransaction` / `OnAttTransactionEx` (real-time attendance push)
- `SSR_SetUserInfo` / `SSR_GetUserInfo`
- `StartEnrollEx`
- `GetUserTmpExStr` (template verification)
- `ReadAllGLogData` + `SSR_GetGeneralLogData`

---

## Troubleshooting

| Error | Fix |
|-------|-----|
| `REGDB_E_CLASSNOTREG` | Run regsvr32 with SysWOW64 path |
| `800700c1` not valid Win32 app | Build **x86**, not x64 |
| Interop not found | Set `ZKTecoSdkPath` to your SDK folder |
| Connect false | Check K50 IP, only one client connected |

---

## Node.js

The previous Node.js backend is **removed**. Use this C# service only.
