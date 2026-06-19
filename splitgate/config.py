import re
from pathlib import Path

from dotenv import dotenv_values

PACKAGE_DIR = Path(__file__).resolve().parent
REPO_ROOT = PACKAGE_DIR.parent
ENV_PATH = REPO_ROOT / ".env"
TEMPLATE_PATH = PACKAGE_DIR / "xray-config.template.json"
RUNTIME_DIR = REPO_ROOT / ".xray"

REQUIRED_KEYS = (
    "SERVER_HOST", "SS_PASSWORD", "SS_PORT", "SS_CIPHER", "SOCKS_PORT", "XRAY_EXE",
    "ALIBABA_ACCESS_KEY_ID", "ALIBABA_ACCESS_KEY_SECRET", "ALIBABA_INSTANCE_ID",
    "ALIBABA_REGION", "PROXY_EIP",
)

_TOKENS = {
    "__SERVER_HOST__": "SERVER_HOST",
    "__SS_PASSWORD__": "SS_PASSWORD",
    "__SS_PORT__": "SS_PORT",
    "__SS_CIPHER__": "SS_CIPHER",
    "__SOCKS_PORT__": "SOCKS_PORT",
}


def load_settings(env_path=ENV_PATH):
    values = dotenv_values(env_path)
    missing = [k for k in REQUIRED_KEYS if not values.get(k)]
    if missing:
        raise ValueError(f"Missing env vars: {', '.join(missing)}")
    return dict(values)


def render_config(settings, template_path=TEMPLATE_PATH, out_path=None):
    out_path = Path(out_path) if out_path else RUNTIME_DIR / "config.json"
    text = Path(template_path).read_text(encoding="utf-8")
    for token, key in _TOKENS.items():
        text = text.replace(token, str(settings[key]))
    leftover = re.search(r"__[A-Z_]+__", text)
    if leftover:
        raise ValueError(f"Unsubstituted token in rendered config: {leftover.group(0)}")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(text, encoding="utf-8")
    return out_path
