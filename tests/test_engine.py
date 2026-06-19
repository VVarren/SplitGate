import pytest
from splitgate import engine


def _pidfile(rt):
    return rt / "xray.pid"


def test_is_running_true_for_live_xray(monkeypatch, tmp_path):
    _pidfile(tmp_path).write_text("123")
    monkeypatch.setattr(engine.psutil, "pid_exists", lambda pid: True)
    monkeypatch.setattr(engine.psutil, "Process",
                        lambda pid: type("P", (), {"name": lambda self: "xray.exe"})())
    assert engine.is_running(tmp_path) == 123


def test_is_running_none_when_pid_reused(monkeypatch, tmp_path):
    _pidfile(tmp_path).write_text("123")
    monkeypatch.setattr(engine.psutil, "pid_exists", lambda pid: True)
    monkeypatch.setattr(engine.psutil, "Process",
                        lambda pid: type("P", (), {"name": lambda self: "notepad.exe"})())
    assert engine.is_running(tmp_path) is None


def test_is_running_none_without_pidfile(tmp_path):
    assert engine.is_running(tmp_path) is None


def test_start_xray_writes_pidfile(monkeypatch, tmp_path):
    monkeypatch.setattr(engine, "is_running", lambda *a, **k: None)
    monkeypatch.setattr(engine.plat, "launch_detached", lambda *a, **k: 555)
    monkeypatch.setattr(engine.psutil, "pid_exists", lambda pid: True)
    monkeypatch.setattr(engine.time, "sleep", lambda s: None)
    engine.start_xray("/bin/xray", tmp_path / "cfg.json", tmp_path)
    assert _pidfile(tmp_path).read_text() == "555"


def test_start_xray_raises_if_exits_immediately(monkeypatch, tmp_path):
    (tmp_path / "xray.log").write_text("boom: bad config")
    monkeypatch.setattr(engine, "is_running", lambda *a, **k: None)
    monkeypatch.setattr(engine.plat, "launch_detached", lambda *a, **k: 556)
    monkeypatch.setattr(engine.psutil, "pid_exists", lambda pid: False)
    monkeypatch.setattr(engine.time, "sleep", lambda s: None)
    with pytest.raises(RuntimeError, match="exited immediately"):
        engine.start_xray("/bin/xray", tmp_path / "cfg.json", tmp_path)


def test_stop_xray_terminates(monkeypatch, tmp_path):
    _pidfile(tmp_path).write_text("777")
    monkeypatch.setattr(engine, "is_running", lambda *a, **k: 777)
    killed = {"v": False}
    monkeypatch.setattr(engine.psutil, "Process",
                        lambda pid: type("P", (), {"terminate": lambda self: killed.__setitem__("v", True)})())
    engine.stop_xray(tmp_path)
    assert killed["v"] is True
    assert not _pidfile(tmp_path).exists()
