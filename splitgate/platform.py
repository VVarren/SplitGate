import platform as _platform
import subprocess

_CREATE_NO_WINDOW = 0x08000000
_DETACHED_PROCESS = 0x00000008


def current_os():
    system = _platform.system()
    if system == "Windows":
        return "windows"
    if system == "Linux":
        return "linux"
    raise RuntimeError(f"Unsupported OS: {system}")


def launch_detached(exe, args, cwd, log_path):
    log = open(log_path, "ab")
    cmd = [exe, *args]
    if current_os() == "windows":
        proc = subprocess.Popen(
            cmd, cwd=cwd, stdout=log, stderr=log,
            creationflags=_CREATE_NO_WINDOW | _DETACHED_PROCESS,
        )
    else:
        proc = subprocess.Popen(
            cmd, cwd=cwd, stdout=log, stderr=log, start_new_session=True,
        )
    return proc.pid
