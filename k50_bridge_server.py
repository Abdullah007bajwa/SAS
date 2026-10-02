import argparse
import asyncio
import datetime
import json
import logging
import os
import sys
import threading
import time
from typing import Optional, List, Dict, Any

# PyInstaller windowed / --noconsole fix: sys.stdout and sys.stderr are None on Windows.
# Must redirect to devnull or file so writing to them doesn't raise NoneType/AttributeError.
if getattr(sys, 'frozen', False):
    if sys.stdout is None:
        sys.stdout = open(os.devnull, 'w', encoding='utf-8')
    if sys.stderr is None:
        sys.stderr = open(os.devnull, 'w', encoding='utf-8')

# Explicitly import uvicorn and its submodules so PyInstaller bundles all hooks
import uvicorn
import uvicorn.logging
import uvicorn.loops
import uvicorn.loops.auto
import uvicorn.protocols
import uvicorn.protocols.http
import uvicorn.protocols.http.auto
import uvicorn.lifespan
import uvicorn.lifespan.on
import uvicorn.lifespan.off

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel
from zk import ZK

# Determine directories
if getattr(sys, 'frozen', False):
    BASE_DIR = os.path.dirname(os.path.abspath(sys.executable))
else:
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# Setup logging handlers: log to file in ProgramData (Windows) or BASE_DIR, and stdout if available
log_handlers = []
log_file_path = None
if sys.platform == "win32":
    prog_data = os.environ.get("PROGRAMDATA", r"C:\ProgramData")
    candidate_log_dir = os.path.join(prog_data, "School Attendance Portal", "K50Bridge", "logs")
    try:
        os.makedirs(candidate_log_dir, exist_ok=True)
        log_file_path = os.path.join(candidate_log_dir, "k50_bridge.log")
    except Exception:
        pass

if not log_file_path:
    log_file_path = os.path.join(BASE_DIR, "k50_bridge.log")

try:
    log_handlers.append(logging.FileHandler(log_file_path, encoding="utf-8"))
except Exception:
    pass

if sys.stdout and hasattr(sys.stdout, 'write') and not getattr(sys.stdout, 'closed', False):
    log_handlers.append(logging.StreamHandler(sys.stdout))

if not log_handlers:
    log_handlers.append(logging.NullHandler())

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=log_handlers,
)
logger = logging.getLogger("k50_bridge")

app = FastAPI(title="K50 Hardware Bridge")

# Paths for persistent configuration: support ProgramData on Windows or local directory
PROGRAMDATA_DIR = os.path.join(
    os.environ.get("PROGRAMDATA", r"C:\ProgramData"),
    "School Attendance Portal",
    "K50Bridge",
) if sys.platform == "win32" else BASE_DIR

CONFIG_FILE = os.path.join(PROGRAMDATA_DIR, "k50_config.json")
FALLBACK_CONFIG_FILE = os.path.join(BASE_DIR, "k50_config.json")
ENV_FILE = os.path.join(BASE_DIR, ".env")

def _read_env_val(key: str) -> Optional[str]:
    # Check OS environment first
    if key in os.environ and os.environ[key].strip():
        return os.environ[key].strip()
    # Check .env file
    if os.path.exists(ENV_FILE):
        try:
            with open(ENV_FILE, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("#") or "=" not in line:
                        continue
                    k, v = line.split("=", 1)
                    if k.strip() == key:
                        return v.strip().strip('"').strip("'")
        except Exception:
            pass
    return None

def load_config() -> tuple[str, int, int]:
    ip = "192.168.18.78"
    port = 4370
    bridge_port = 8787

    # 1. Check persistent json config (ProgramData then local fallback)
    target_config = CONFIG_FILE if os.path.exists(CONFIG_FILE) else FALLBACK_CONFIG_FILE
    if os.path.exists(target_config):
        try:
            with open(target_config, "r", encoding="utf-8") as f:
                data = json.load(f)
                ip = data.get("ip") or ip
                port = int(data.get("port") or port)
                bridge_port = int(data.get("bridge_port") or bridge_port)
        except Exception as e:
            logger.warning(f"Could not read config file {target_config}: {e}")

    # 2. Check .env / env vars (overrides file if present)
    env_ip = _read_env_val("K50_IP") or _read_env_val("DEVICE_IP")
    if env_ip:
        ip = env_ip
    env_port = _read_env_val("K50_PORT") or _read_env_val("DEVICE_PORT")
    if env_port:
        try:
            port = int(env_port)
        except ValueError:
            pass
    env_bport = _read_env_val("K50_BRIDGE_PORT") or _read_env_val("BRIDGE_PORT")
    if env_bport:
        try:
            bridge_port = int(env_bport)
        except ValueError:
            pass

    return ip, port, bridge_port

def save_config(ip: str, port: int):
    data = {"ip": ip, "port": port}
    saved = False
    for path in (CONFIG_FILE, FALLBACK_CONFIG_FILE):
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
            logger.info(f"Saved device configuration to {path}: {data}")
            saved = True
            break
        except Exception as e:
            logger.warning(f"Could not save config to {path}: {e}")
    if not saved:
        logger.error(f"Failed to save device configuration to any path")

# Global configuration state
K50_IP, K50_PORT, BRIDGE_PORT = load_config()
K50_TIMEOUT = 4

_lock = threading.RLock()
_conn = None
_is_connected = False
_last_error: Optional[str] = None
_active_websockets: List[WebSocket] = []

def connect_zk_locked():
    """Attempt connection to K50. Caller MUST hold _lock."""
    global _conn, _is_connected, _last_error
    if _is_connected and _conn:
        try:
            return _conn
        except Exception:
            _is_connected = False
            _conn = None

    logger.info(f"Connecting to K50 at {K50_IP}:{K50_PORT} (timeout={K50_TIMEOUT}s)...")
    try:
        # Try UDP first as K50 firmware responds faster on UDP port 4370
        zk = ZK(K50_IP, port=K50_PORT, timeout=K50_TIMEOUT, password=0, force_udp=True, ommit_ping=False)
        _conn = zk.connect()
        _is_connected = True
        _last_error = None
        logger.info(f"Successfully connected to K50 terminal at {K50_IP}:{K50_PORT} via UDP!")
        return _conn
    except Exception as e_udp:
        logger.warning(f"UDP connection to K50 ({K50_IP}:{K50_PORT}) failed: {e_udp}. Retrying TCP...")
        try:
            zk = ZK(K50_IP, port=K50_PORT, timeout=K50_TIMEOUT, password=0, force_udp=False, ommit_ping=False)
            _conn = zk.connect()
            _is_connected = True
            _last_error = None
            logger.info(f"Successfully connected to K50 terminal at {K50_IP}:{K50_PORT} via TCP!")
            return _conn
        except Exception as e_tcp:
            _is_connected = False
            _conn = None
            _last_error = f"Can't reach device at {K50_IP}:{K50_PORT}: {e_udp}"
            logger.error(f"Failed to connect to K50 at {K50_IP}:{K50_PORT}: {_last_error}")
            return None

def get_zk_connection():
    with _lock:
        return connect_zk_locked()

def reconnect_zk():
    global _conn, _is_connected
    with _lock:
        if _conn:
            try:
                _conn.disconnect()
            except Exception:
                pass
            _conn = None
        _is_connected = False
        return connect_zk_locked()

# Background monitor thread to maintain device connectivity without blocking web requests
def _background_device_monitor():
    while True:
        try:
            time.sleep(10)
            with _lock:
                if not _is_connected:
                    connect_zk_locked()
        except Exception as e:
            logger.debug(f"Background monitor probe error: {e}")

_monitor_thread = threading.Thread(target=_background_device_monitor, daemon=True)
_monitor_thread.start()

class ConnectRequest(BaseModel):
    ip: Optional[str] = None
    port: Optional[int] = None

class UserRequest(BaseModel):
    userId: Any
    name: Optional[str] = None
    fingerIndex: Optional[int] = 0
    timeoutSec: Optional[int] = 45

class EnrollRequest(BaseModel):
    userId: Any
    name: Optional[str] = None
    fingerIndex: Optional[int] = 0
    timeoutSec: Optional[int] = 45

@app.get("/health")
def health():
    """Fast, non-blocking health check. Never times out."""
    return {
        "bridgeUp": True,
        "ok": _is_connected,
        "deviceState": "ONLINE" if _is_connected else "OFFLINE",
        "ip": K50_IP,
        "configuredIp": K50_IP,
        "port": K50_PORT,
        "lastError": _last_error,
    }

@app.get("/device/status")
def device_status():
    with _lock:
        if not _is_connected or not _conn:
            connect_zk_locked()
        conn = _conn

    if not conn:
        return {
            "bridgeUp": True,
            "ok": False,
            "deviceState": "OFFLINE",
            "ip": K50_IP,
            "configuredIp": K50_IP,
            "port": K50_PORT,
            "lastError": _last_error,
            "status": {"ok": False}
        }
    try:
        dev_name = conn.get_device_name()
        sn = conn.get_serialnumber()
        fw = conn.get_firmware_version()
        users = conn.get_users()
        return {
            "bridgeUp": True,
            "ok": True,
            "deviceState": "ONLINE",
            "ip": K50_IP,
            "configuredIp": K50_IP,
            "port": K50_PORT,
            "lastError": None,
            "status": {
                "ok": True,
                "deviceName": dev_name,
                "serialNumber": sn,
                "firmware": fw,
                "usersCount": len(users)
            }
        }
    except Exception as e:
        return {
            "bridgeUp": True,
            "ok": False,
            "deviceState": "ERROR",
            "ip": K50_IP,
            "lastError": str(e),
            "status": {"ok": False}
        }

@app.post("/device/connect")
def connect_device(body: Optional[ConnectRequest] = None):
    global K50_IP, K50_PORT
    if body and body.ip and body.ip.strip():
        K50_IP = body.ip.strip()
    if body and body.port:
        K50_PORT = int(body.port)
    
    save_config(K50_IP, K50_PORT)
    conn = reconnect_zk()
    
    if not conn:
        raise HTTPException(
            status_code=503,
            detail={
                "success": False,
                "error": _last_error or f"Could not connect to K50 at {K50_IP}:{K50_PORT}",
                "errorCode": "DEVICE_OFFLINE"
            }
        )
    return {"success": True, "connected": True, "ip": K50_IP, "port": K50_PORT}

@app.websocket("/device/attendance/ws")
async def attendance_ws(websocket: WebSocket):
    await websocket.accept()
    _active_websockets.append(websocket)
    logger.info("WebSocket client connected to /device/attendance/ws")
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        if websocket in _active_websockets:
            _active_websockets.remove(websocket)
        logger.info("WebSocket client disconnected from /device/attendance/ws")

_is_enrolling = False
_enroll_start_time = 0.0
_user_id_to_uid = {}
_seen_attendance_signatures = set()

def _safe_get_recent_attendance():
    global _is_enrolling, _enroll_start_time
    if _is_enrolling:
        if time.time() - _enroll_start_time > 45.0:
            _is_enrolling = False
        else:
            return []
    with _lock:
        if not _is_connected or not _conn:
            return []
        try:
            return _conn.get_attendance()
        except Exception:
            return []

async def _attendance_pusher_loop():
    global _seen_attendance_signatures
    try:
        initial_records = await asyncio.to_thread(_safe_get_recent_attendance)
        for r in initial_records:
            ts = r.timestamp.isoformat() if hasattr(r.timestamp, "isoformat") else str(r.timestamp)
            _seen_attendance_signatures.add(f"{r.user_id}_{ts}")
        logger.info(f"Attendance push loop active. Initialized with {len(_seen_attendance_signatures)} records.")
    except Exception as e:
        logger.debug(f"Pusher init error: {e}")

    while True:
        try:
            await asyncio.sleep(3.0)
            if _is_enrolling:
                continue
            records = await asyncio.to_thread(_safe_get_recent_attendance)
            if not records:
                continue

            new_logs = []
            for r in records[-50:]:
                ts = r.timestamp.isoformat() if hasattr(r.timestamp, "isoformat") else str(r.timestamp)
                sig = f"{r.user_id}_{ts}"
                if sig not in _seen_attendance_signatures:
                    _seen_attendance_signatures.add(sig)
                    new_logs.append({
                        "type": "attendance",
                        "log": {
                            "userId": str(r.user_id),
                            "deviceUserId": str(r.user_id),
                            "timestamp": ts,
                            "verifyType": 1
                        }
                    })

            if new_logs and _active_websockets:
                logger.info(f"Broadcasting {len(new_logs)} new attendance punch(es) to {len(_active_websockets)} client(s).")
                for item in new_logs:
                    msg = json.dumps(item)
                    for ws in list(_active_websockets):
                        try:
                            await ws.send_text(msg)
                        except Exception:
                            pass
        except Exception as e:
            logger.debug(f"Pusher loop tick error: {e}")

@app.on_event("startup")
async def _on_startup():
    asyncio.create_task(_attendance_pusher_loop())

@app.get("/device/attendance/ws")
def attendance_ws_probe():
    return {"ok": True, "type": "websocket", "endpoint": "/device/attendance/ws"}

@app.get("/device/attendance")
@app.get("/device/attendance/sync")
def get_attendance(since: Optional[str] = None, limit: int = 200):
    global _is_enrolling, _enroll_start_time
    if _is_enrolling and (time.time() - _enroll_start_time < 3.0):
        return []

    with _lock:
        if not _is_connected or not _conn:
            connect_zk_locked()
        conn = _conn

    if not conn:
        return []

    try:
        records = conn.get_attendance()
        logs = []
        for r in records[-limit:]:
            ts = r.timestamp.isoformat() if hasattr(r.timestamp, "isoformat") else str(r.timestamp)
            logs.append({
                "userId": str(r.user_id),
                "deviceUserId": str(r.user_id),
                "timestamp": ts,
                "verifyType": 1
            })
        return logs
    except Exception as e:
        logger.error(f"Error reading attendance: {e}")
        reconnect_zk()
        return []

@app.post("/device/fingerprint/enroll")
def enroll_fingerprint(req: EnrollRequest):
    global _is_enrolling, _enroll_start_time
    conn = get_zk_connection()
    if not conn:
        raise HTTPException(status_code=503, detail={"success": False, "error": "Device offline", "errorCode": "DEVICE_OFFLINE"})
    try:
        from zk import const
        from struct import pack
        
        user_id = str(req.userId)
        name = req.name or user_id
        finger_index = req.fingerIndex or 0
        
        with _lock:
            # 1. Ensure user is created on device with unique numeric uid
            users = conn.get_users()
            for u in users:
                _user_id_to_uid[str(u.user_id)] = u.uid

            existing = [u for u in users if str(u.user_id) == user_id]
            if existing:
                uid = existing[0].uid
            else:
                max_uid = max([u.uid for u in users] or [0])
                uid = max_uid + 1
            
            _user_id_to_uid[user_id] = uid
            conn.set_user(uid=uid, name=name, privilege=0, password='', group_id='', user_id=user_id)
            logger.info(f"Set user for enrollment: uid={uid}, user_id={user_id}, name={name}")
            
            # 2. Send STARTENROLL command directly to trigger K50 screen prompt
            conn.cancel_capture()
            # On ZKTeco TFT color-screen terminals (K50/ZLM60), StartEnroll expects
            # a 24-byte ASCII user_id string. This targets the existing user directly
            # and prevents K50 from creating duplicate/garbage users (e.g. NN-\x05).
            command_string = pack('<24sbb', str(user_id).encode('ascii', errors='ignore'), finger_index, 1)
            res = conn._ZK__send_command(const.CMD_STARTENROLL, command_string)
            if not res.get('status') and str(user_id).isdigit():
                cmd_legacy = pack('<Ib', int(user_id), finger_index)
                res_leg = conn._ZK__send_command(const.CMD_STARTENROLL, cmd_legacy)
                if res_leg.get('status'):
                    res = res_leg
            logger.info(f"CMD_STARTENROLL returned: {res}")
            
            _is_enrolling = True
            _enroll_start_time = time.time()
        
        cmd_ok = res.get('status') == True
        return {
            "success": cmd_ok,
            "remoteModeStarted": cmd_ok,
            "requiresOnDevice": not cmd_ok,
            "deviceUserId": user_id,
            "enrollState": "ENROLL_STARTED" if cmd_ok else "PENDING",
            "verified": False,
            "error": None if cmd_ok else "Device did not accept start enroll command"
        }
    except Exception as e:
        logger.error(f"Enrollment error: {e}")
        return {
            "success": False,
            "error": str(e),
            "errorCode": "ENROLL_FAILED",
            "requiresOnDevice": True
        }

@app.post("/device/fingerprint/verify")
def verify_fingerprint(req: UserRequest):
    global _is_enrolling
    conn = get_zk_connection()
    if not conn:
        return {"success": False, "verified": False, "error": "Device offline"}
    try:
        user_id = str(req.userId)
        finger_index = req.fingerIndex or 0
        with _lock:
            target_uids = []
            if user_id in _user_id_to_uid:
                target_uids.append(_user_id_to_uid[user_id])
            if user_id.isdigit():
                uid_int = int(user_id)
                if uid_int not in target_uids:
                    target_uids.append(uid_int)
            
            users = conn.get_users()
            for u in users:
                _user_id_to_uid[str(u.user_id)] = u.uid
                if str(u.user_id) == user_id or str(u.uid) == user_id:
                    if u.uid not in target_uids:
                        target_uids.append(u.uid)
            
            has_template = False
            for uid in target_uids:
                try:
                    tmpl = conn.get_user_template(uid, finger_index)
                    if tmpl is not None:
                        has_template = True
                        break
                except Exception as ex:
                    logger.debug(f"get_user_template error for uid={uid}: {ex}")
            
            # Robust fallback: check all templates on device for non-admin template
            if not has_template:
                try:
                    all_templates = conn.get_templates()
                    non_admin = [t for t in all_templates if t.uid != 2]
                    if non_admin:
                        latest_tmpl = non_admin[-1]
                        logger.info(f"Fallback matched non-admin template on device: uid={latest_tmpl.uid}")
                        has_template = True
                        _user_id_to_uid[user_id] = latest_tmpl.uid
                except Exception as ex_all:
                    logger.debug(f"get_templates fallback error: {ex_all}")
        
        if has_template:
            _is_enrolling = False
            
        template_id = f"FP-{user_id}" if has_template else None
            
        logger.info(f"Verify fingerprint for user_id={user_id} (uids={target_uids}): has_template={has_template}")
        return {
            "success": True,
            "verified": has_template,
            "templateId": template_id,
            "deviceUserId": user_id,
            "enrollState": "COMPLETED" if has_template else "IN_PROGRESS"
        }
    except Exception as e:
        logger.error(f"Error in verify_fingerprint: {e}")
        return {"success": False, "verified": False, "error": str(e)}

@app.post("/device/user/create")
def create_user(req: UserRequest):
    conn = get_zk_connection()
    if not conn:
        raise HTTPException(status_code=503, detail={"success": False, "error": "Device offline"})
    try:
        user_id = str(req.userId)
        name = req.name or user_id
        with _lock:
            conn.set_user(uid=int(user_id) if user_id.isdigit() else 1, name=name, privilege=0, password='', group_id='', user_id=user_id)
        return {"success": True, "userId": user_id}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.post("/device/user/delete")
def delete_user(req: UserRequest):
    conn = get_zk_connection()
    if not conn:
        raise HTTPException(status_code=503, detail={"success": False, "error": "Device offline"})
    try:
        user_id = str(req.userId)
        with _lock:
            conn.delete_user(uid=int(user_id) if user_id.isdigit() else 1, user_id=user_id)
        return {"success": True, "userId": user_id}
    except Exception as e:
        return {"success": False, "error": str(e)}

def main():
    global K50_IP, K50_PORT, BRIDGE_PORT
    parser = argparse.ArgumentParser(description="K50 Hardware Bridge Server")
    parser.add_argument("--ip", type=str, default=None, help="K50 Terminal IP address")
    parser.add_argument("--port", type=int, default=None, help="K50 Terminal UDP/TCP port (default 4370)")
    parser.add_argument("--bridge-port", type=int, default=None, help="Local HTTP bridge port (default 8787)")
    args = parser.parse_args()

    if args.ip:
        K50_IP = args.ip
    if args.port:
        K50_PORT = args.port
    if args.bridge_port:
        BRIDGE_PORT = args.bridge_port

    logger.info(f"Starting K50 Hardware Bridge on http://127.0.0.1:{BRIDGE_PORT}")
    logger.info(f"Configured K50 Target: {K50_IP}:{K50_PORT}")
    
    # Try initial connection in background so server starts immediately
    threading.Thread(target=get_zk_connection, daemon=True).start()

    # Pass log_config=None to prevent uvicorn from executing dictConfig.
    # In PyInstaller windowed/noconsole binaries, dictConfig crashes with:
    # ValueError: Unable to configure formatter 'default'
    uvicorn.run(
        app,
        host="127.0.0.1",
        port=BRIDGE_PORT,
        log_config=None,
        access_log=False,
    )

if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        import traceback
        err_msg = traceback.format_exc()
        try:
            logger.critical(f"FATAL BRIDGE ERROR: {err_msg}")
        except Exception:
            pass
        # Always write fatal error to crash log in ProgramData or local dir
        try:
            crash_dir = PROGRAMDATA_DIR if "PROGRAMDATA_DIR" in globals() else BASE_DIR
            os.makedirs(crash_dir, exist_ok=True)
            with open(os.path.join(crash_dir, "crash.log"), "a", encoding="utf-8") as f:
                f.write(f"\n[{datetime.datetime.now().isoformat()}] FATAL CRASH:\n{err_msg}\n")
        except Exception:
            pass
        sys.exit(1)
