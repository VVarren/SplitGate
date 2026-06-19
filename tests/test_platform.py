import builtins
import pytest
from splitgate import platform as plat


def test_current_os_returns_known(monkeypatch):
    monkeypatch.setattr(plat._platform, "system", lambda: "Linux")
    assert plat.current_os() == "linux"
    monkeypatch.setattr(plat._platform, "system", lambda: "Windows")
    assert plat.current_os() == "windows"


def test_current_os_unsupported_raises(monkeypatch):
    monkeypatch.setattr(plat._platform, "system", lambda: "Darwin")
    with pytest.raises(RuntimeError, match="Unsupported OS"):
        plat.current_os()


def test_launch_detached_linux_uses_new_session(monkeypatch, tmp_path):
    captured = {}

    class FakePopen:
        def __init__(self, cmd, **kw):
            captured["cmd"] = cmd
            captured["kw"] = kw
            self.pid = 4321

    monkeypatch.setattr(plat, "current_os", lambda: "linux")
    monkeypatch.setattr(plat.subprocess, "Popen", FakePopen)
    monkeypatch.setattr(builtins, "open", lambda *a, **k: object())
    pid = plat.launch_detached("/bin/xray", ["-c", "cfg"], "/cwd", str(tmp_path / "log"))
    assert pid == 4321
    assert captured["cmd"] == ["/bin/xray", "-c", "cfg"]
    assert captured["kw"].get("start_new_session") is True


def test_launch_detached_windows_uses_no_window(monkeypatch, tmp_path):
    captured = {}

    class FakePopen:
        def __init__(self, cmd, **kw):
            captured["kw"] = kw
            self.pid = 99

    monkeypatch.setattr(plat, "current_os", lambda: "windows")
    monkeypatch.setattr(plat.subprocess, "Popen", FakePopen)
    monkeypatch.setattr(builtins, "open", lambda *a, **k: object())
    plat.launch_detached("xray.exe", ["-c", "cfg"], "cwd", str(tmp_path / "log"))
    assert captured["kw"].get("creationflags") == (0x08000000 | 0x00000008)
