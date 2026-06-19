import time
from pathlib import Path

import psutil

from . import platform as plat


def _pidfile(runtime_dir):
    return Path(runtime_dir) / "xray.pid"


def is_running(runtime_dir, proc_name="xray"):
    pidfile = _pidfile(runtime_dir)
    if not pidfile.exists():
        return None
    try:
        pid = int(pidfile.read_text().strip())
    except ValueError:
        return None
    if not psutil.pid_exists(pid):
        return None
    try:
        if proc_name in psutil.Process(pid).name().lower():
            return pid
    except psutil.Error:
        return None
    return None


def start_xray(exe, config_path, runtime_dir):
    runtime_dir = Path(runtime_dir)
    runtime_dir.mkdir(parents=True, exist_ok=True)
    if is_running(runtime_dir):
        print("xray already running.")
        return
    log = runtime_dir / "xray.log"
    pid = plat.launch_detached(exe, ["-c", str(config_path)],
                               cwd=str(Path(exe).parent), log_path=str(log))
    _pidfile(runtime_dir).write_text(str(pid))
    time.sleep(1)
    if not psutil.pid_exists(pid):
        tail = "\n".join(log.read_text(errors="ignore").splitlines()[-20:]) if log.exists() else ""
        raise RuntimeError(f"xray exited immediately. Log tail:\n{tail}")
    print(f"Launched xray (PID {pid}).")


def stop_xray(runtime_dir):
    pid = is_running(runtime_dir)
    if not pid:
        print("xray not running.")
        return
    psutil.Process(pid).terminate()
    _pidfile(runtime_dir).unlink(missing_ok=True)
    print("Stopped xray.")
