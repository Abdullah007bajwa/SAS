import asyncio
import datetime
import logging
import threading
import time
from typing import Optional, List, Dict, Any
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel
from zk import ZK

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("k50_bridge")

app = FastAPI(title="K50 Hardware Bridge")

# Global device state
K50_IP = "192.168.100.18"
K50_PORT = 4370
K50_TIMEOUT = 5

_lock = threading.Lock()
_conn = None
_is_connected = False
_last_error: Optional[str] = None
_recent_attendance: List[Dict[str, Any]] = []

def get_zk_connection():
    global _conn, _is_connected, _last_error
    if _is_connected and _conn:
        try:
            return _conn
        except Exception:
            _is_connected = False
            _conn = None
    
    try:
        logger.info(f"Connecting to K50 at {K50_IP}:{K50_PORT}...")
        zk = ZK(K50_IP, port=K50_PORT, timeout=K50_TIMEOUT, password=0, force_udp=False, ommit_ping=False)
        _conn = zk.connect()
        _is_connected = True
        _last_error = None
        logger.info("Successfully connected to K50 terminal!")
        return _conn
    except Exception as e:
        _is_connected = False
        _last_error = str(e)
        logger.warning(f"Failed to connect to K50 via TCP, retrying UDP: {e}")
        try:
            zk = ZK(K50_IP, port=K50_PORT, timeout=K50_TIMEOUT, password=0, force_udp=True, ommit_ping=False)
            _conn = zk.connect()
            _is_connected = True
            _last_error = None
            logger.info("Successfully connected to K50 terminal via UDP!")
            return _conn
        except Exception as e2:
            _is_connected = False
            _last_error = str(e2)
            logger.error(f"Failed to connect to K50 via UDP: {e2}")
            return None

class ConnectRequest(BaseModel):
    ip: Optional[str] = None
    port: Optional[int] = None

class UserRequest(BaseModel):
    userId: str
    name: Optional[str] = None
    fingerIndex: Optional[int] = 0
    timeoutSec: Optional[int] = 45

class EnrollRequest(BaseModel):
    userId: str
    name: str
    fingerIndex: Optional[int] = 0
    timeoutSec: Optional[int] = 45

@app.get("/health")
def health():
    global _is_connected, _last_error
    # Probe device
    with _lock:
        conn = get_zk_connection()
        device_online = conn is not None
    
    return {
        "bridgeUp": True,
        "ok": device_online,
        "deviceState": "ONLINE" if device_online else "OFFLINE",
        "ip": K50_IP,
        "configuredIp": K50_IP,
        "port": K50_PORT,
        "lastError": _last_error,
    }

@app.get("/device/status")
def device_status():
    with _lock:
        conn = get_zk_connection()
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
    global K50_IP, K50_PORT, _conn, _is_connected
    if body and body.ip:
        K50_IP = body.ip
    if body and body.port:
        K50_PORT = body.port
    
    with _lock:
        if _conn:
            try:
                _conn.disconnect()
            except Exception:
                pass
            _conn = None
            _is_connected = False
        conn = get_zk_connection()
        if not conn:
            raise HTTPException(status_code=503, detail={"success": False, "error": _last_error or "Connect failed", "errorCode": "DEVICE_OFFLINE"})
        return {"success": True, "connected": True, "ip": K50_IP, "port": K50_PORT}

@app.get("/device/attendance")
@app.get("/device/attendance/sync")
def get_attendance(since: Optional[str] = None, limit: int = 200):
    with _lock:
        conn = get_zk_connection()
        if not conn:
            return {"success": False, "logs": [], "deviceState": "OFFLINE"}
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
            return []

@app.post("/device/fingerprint/enroll")
def enroll_fingerprint(req: EnrollRequest):
    with _lock:
        conn = get_zk_connection()
        if not conn:
            raise HTTPException(status_code=503, detail={"success": False, "error": "Device offline", "errorCode": "DEVICE_OFFLINE"})
        try:
            # Set user on device if not present
            user_id = str(req.userId)
            name = req.name or user_id
            conn.set_user(uid=int(user_id) if user_id.isdigit() else 1, name=name, privilege=0, password='', group_id='', user_id=user_id)
            
            # Start enrollment on device: ZK enrollment command
            conn.enroll_user(uid=user_id)
            return {
                "success": True,
                "remoteModeStarted": True,
                "deviceUserId": user_id,
                "enrollState": "ENROLL_STARTED",
                "verified": False
            }
        except Exception as e:
            logger.error(f"Enrollment error: {e}")
            return {
                "success": False,
                "error": str(e),
                "errorCode": "ENROLL_FAILED"
            }

@app.post("/device/fingerprint/verify")
def verify_fingerprint(req: UserRequest):
    with _lock:
        conn = get_zk_connection()
        if not conn:
            return {"success": False, "verified": False, "error": "Device offline"}
        try:
            templates = conn.get_templates()
            user_id = str(req.userId)
            has_template = any(str(t.uid) == user_id or str(t.user_id) == user_id for t in templates)
            return {
                "success": True,
                "verified": has_template,
                "deviceUserId": user_id,
                "enrollState": "COMPLETED" if has_template else "IN_PROGRESS"
            }
        except Exception as e:
            return {"success": False, "verified": False, "error": str(e)}

@app.post("/device/user/create")
def create_user(req: UserRequest):
    with _lock:
        conn = get_zk_connection()
        if not conn:
            raise HTTPException(status_code=503, detail={"success": False, "error": "Device offline"})
        try:
            user_id = str(req.userId)
            name = req.name or user_id
            conn.set_user(uid=int(user_id) if user_id.isdigit() else 1, name=name, privilege=0, password='', group_id='', user_id=user_id)
            return {"success": True, "userId": user_id}
        except Exception as e:
            return {"success": False, "error": str(e)}

@app.post("/device/user/delete")
def delete_user(req: UserRequest):
    with _lock:
        conn = get_zk_connection()
        if not conn:
            raise HTTPException(status_code=503, detail={"success": False, "error": "Device offline"})
        try:
            user_id = str(req.userId)
            conn.delete_user(uid=int(user_id) if user_id.isdigit() else 1, user_id=user_id)
            return {"success": True, "userId": user_id}
        except Exception as e:
            return {"success": False, "error": str(e)}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8787)
