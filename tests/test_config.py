import json
import pytest
from splitgate import config

SETTINGS = {
    "SERVER_HOST": "203.0.113.10", "SS_PASSWORD": "pw1", "SS_PORT": "443",
    "SS_CIPHER": "chacha20-ietf-poly1305", "SOCKS_PORT": "10808",
    "XRAY_EXE": "/usr/local/bin/xray", "ALIBABA_ACCESS_KEY_ID": "k",
    "ALIBABA_ACCESS_KEY_SECRET": "s", "ALIBABA_INSTANCE_ID": "i-1",
    "ALIBABA_REGION": "cn-hangzhou", "PROXY_EIP": "203.0.113.10",
}


def test_load_settings_missing_key_raises(tmp_path):
    env = tmp_path / ".env"
    env.write_text("SERVER_HOST=1.2.3.4\n", encoding="utf-8")
    with pytest.raises(ValueError, match="Missing env vars"):
        config.load_settings(env)


def test_render_substitutes_tokens_and_is_valid_json(tmp_path):
    tmpl = tmp_path / "t.json"
    tmpl.write_text(
        '{ "h": "__SERVER_HOST__", "p": __SS_PORT__, "pw": "__SS_PASSWORD__",'
        ' "m": "__SS_CIPHER__", "in": __SOCKS_PORT__ }', encoding="utf-8")
    out = tmp_path / "out" / "config.json"
    result = config.render_config(SETTINGS, template_path=tmpl, out_path=out)
    assert result == out
    data = json.loads(out.read_text(encoding="utf-8"))
    assert data["h"] == "203.0.113.10"
    assert data["p"] == 443 and data["in"] == 10808


def test_render_has_no_utf8_bom(tmp_path):
    tmpl = tmp_path / "t.json"
    tmpl.write_text('{ "h": "__SERVER_HOST__", "p": __SS_PORT__, "pw": "__SS_PASSWORD__",'
                    ' "m": "__SS_CIPHER__", "in": __SOCKS_PORT__ }', encoding="utf-8")
    out = tmp_path / "config.json"
    config.render_config(SETTINGS, template_path=tmpl, out_path=out)
    assert out.read_bytes()[:3] != b"\xef\xbb\xbf"


def test_render_unsubstituted_token_raises(tmp_path):
    tmpl = tmp_path / "t.json"
    tmpl.write_text('{ "x": "__UNKNOWN__" }', encoding="utf-8")
    with pytest.raises(ValueError, match="Unsubstituted token"):
        config.render_config(SETTINGS, template_path=tmpl, out_path=tmp_path / "o.json")
