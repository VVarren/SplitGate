from splitgate import cli


def test_no_args_returns_1_and_prints_usage(capsys):
    rc = cli.main([])
    assert rc == 1
    assert "Usage" in capsys.readouterr().err


def test_unknown_command_returns_1(capsys):
    rc = cli.main(["bogus"])
    assert rc == 1
    assert "Usage" in capsys.readouterr().err


def _patch_all(monkeypatch, order):
    monkeypatch.setattr(cli.config, "load_settings", lambda: {"XRAY_EXE": "x", "SOCKS_PORT": "10808"})
    monkeypatch.setattr(cli.config, "render_config", lambda s: order.append("render") or "cfg")
    monkeypatch.setattr(cli.cloud, "cloud_on", lambda s: order.append("cloud_on"))
    monkeypatch.setattr(cli.cloud, "cloud_off", lambda s: order.append("cloud_off"))
    monkeypatch.setattr(cli.engine, "start_xray", lambda *a: order.append("start"))
    monkeypatch.setattr(cli.engine, "stop_xray", lambda d: order.append("stop"))
    monkeypatch.setattr(cli.sysproxy, "set_proxy", lambda h, p: order.append("set"))
    monkeypatch.setattr(cli.sysproxy, "clear_proxy", lambda: order.append("clear"))


def test_on_runs_in_order(monkeypatch):
    order = []
    _patch_all(monkeypatch, order)
    assert cli.main(["on"]) == 0
    assert order == ["render", "cloud_on", "start", "set"]


def test_off_runs_in_reverse_order(monkeypatch):
    order = []
    _patch_all(monkeypatch, order)
    assert cli.main(["off"]) == 0
    assert order == ["clear", "stop", "cloud_off"]
