from splitgate import cloud

SETTINGS = {
    "ALIBABA_ACCESS_KEY_ID": "k", "ALIBABA_ACCESS_KEY_SECRET": "s",
    "ALIBABA_INSTANCE_ID": "i-1", "ALIBABA_REGION": "cn-hangzhou",
    "PROXY_EIP": "203.0.113.10",
}


def test_cloud_on_starts_stopped_instance(monkeypatch):
    started = {"v": False}

    class FakeClient:
        def start_instance(self, req):
            started["v"] = True

    monkeypatch.setattr(cloud, "get_status", lambda *a, **k: "Stopped")
    monkeypatch.setattr(cloud, "wait_for", lambda *a, **k: None)
    cloud.cloud_on(SETTINGS, client=FakeClient())
    assert started["v"] is True


def test_cloud_on_noop_when_running(monkeypatch):
    started = {"v": False}

    class FakeClient:
        def start_instance(self, req):
            started["v"] = True

    monkeypatch.setattr(cloud, "get_status", lambda *a, **k: "Running")
    cloud.cloud_on(SETTINGS, client=FakeClient())
    assert started["v"] is False


def test_cloud_off_stops_running_instance(monkeypatch):
    stopped = {"v": False}

    class FakeClient:
        def stop_instance(self, req):
            stopped["v"] = True

    monkeypatch.setattr(cloud, "get_status", lambda *a, **k: "Running")
    monkeypatch.setattr(cloud, "wait_for", lambda *a, **k: None)
    cloud.cloud_off(SETTINGS, client=FakeClient())
    assert stopped["v"] is True
