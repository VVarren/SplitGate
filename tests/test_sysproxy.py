import sys
import types
from splitgate import sysproxy


def test_set_proxy_linux_gnome_calls_gsettings(monkeypatch):
    monkeypatch.setattr(sysproxy.plat, "current_os", lambda: "linux")
    monkeypatch.setattr(sysproxy, "_gnome", lambda: True)
    calls = []
    monkeypatch.setattr(sysproxy.subprocess, "run",
                        lambda args, **k: calls.append(args))
    sysproxy.set_proxy("127.0.0.1", "10808")
    assert any("manual" in a for a in calls)
    assert any("10808" in a for a in calls)


def test_set_proxy_linux_non_gnome_is_noop(monkeypatch, capsys):
    monkeypatch.setattr(sysproxy.plat, "current_os", lambda: "linux")
    monkeypatch.setattr(sysproxy, "_gnome", lambda: False)
    called = {"v": False}
    monkeypatch.setattr(sysproxy.subprocess, "run",
                        lambda *a, **k: called.__setitem__("v", True))
    sysproxy.set_proxy("127.0.0.1", "10808")
    assert called["v"] is False
    assert "10808" in capsys.readouterr().out


def test_set_proxy_windows_writes_registry(monkeypatch):
    monkeypatch.setattr(sysproxy.plat, "current_os", lambda: "windows")
    writes = []
    fake = types.SimpleNamespace(
        HKEY_CURRENT_USER=0, KEY_SET_VALUE=2, REG_SZ=1, REG_DWORD=4,
        OpenKey=lambda *a, **k: "KEY",
        SetValueEx=lambda key, name, r, t, v: writes.append((name, v)),
        CloseKey=lambda key: None,
    )
    monkeypatch.setitem(sys.modules, "winreg", fake)
    sysproxy.set_proxy("127.0.0.1", "10808")
    names = dict(writes)
    assert names["ProxyServer"] == "127.0.0.1:10808"
    assert names["ProxyEnable"] == 1


def test_clear_proxy_windows_disables(monkeypatch):
    monkeypatch.setattr(sysproxy.plat, "current_os", lambda: "windows")
    writes = []
    fake = types.SimpleNamespace(
        HKEY_CURRENT_USER=0, KEY_SET_VALUE=2, REG_SZ=1, REG_DWORD=4,
        OpenKey=lambda *a, **k: "KEY",
        SetValueEx=lambda key, name, r, t, v: writes.append((name, v)),
        CloseKey=lambda key: None,
    )
    monkeypatch.setitem(sys.modules, "winreg", fake)
    sysproxy.clear_proxy()
    assert dict(writes)["ProxyEnable"] == 0
