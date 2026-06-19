import sys

from . import cloud, config, engine, sysproxy

COMMANDS = {"on", "off", "status"}


def _on(settings):
    cfg = config.render_config(settings)
    cloud.cloud_on(settings)
    engine.start_xray(settings["XRAY_EXE"], cfg, config.RUNTIME_DIR)
    sysproxy.set_proxy("127.0.0.1", settings["SOCKS_PORT"])
    return 0


def _off(settings):
    sysproxy.clear_proxy()
    engine.stop_xray(config.RUNTIME_DIR)
    cloud.cloud_off(settings)
    return 0


def _status(settings):
    cloud.cloud_status(settings)
    print("xray: running" if engine.is_running(config.RUNTIME_DIR) else "xray: not running")
    return 0


def main(argv=None):
    if argv is None:
        argv = sys.argv[1:]
    if len(argv) != 1 or argv[0] not in COMMANDS:
        print(f"Usage: proxy <{' | '.join(sorted(COMMANDS))}>", file=sys.stderr)
        return 1
    settings = config.load_settings()
    return {"on": _on, "off": _off, "status": _status}[argv[0]](settings)
