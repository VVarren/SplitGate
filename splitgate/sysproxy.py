import os
import shutil
import subprocess

from . import platform as plat

_WIN_REG_PATH = r"Software\Microsoft\Windows\CurrentVersion\Internet Settings"


def _gnome():
    desktop = os.environ.get("XDG_CURRENT_DESKTOP", "").lower()
    return bool(shutil.which("gsettings")) and "gnome" in desktop


def set_proxy(host, port):
    if plat.current_os() == "windows":
        import winreg
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, _WIN_REG_PATH, 0, winreg.KEY_SET_VALUE)
        winreg.SetValueEx(key, "ProxyServer", 0, winreg.REG_SZ, f"{host}:{port}")
        winreg.SetValueEx(key, "ProxyEnable", 0, winreg.REG_DWORD, 1)
        winreg.CloseKey(key)
        print(f"System proxy set to {host}:{port}.")
    elif _gnome():
        subprocess.run(["gsettings", "set", "org.gnome.system.proxy", "mode", "manual"], check=True)
        subprocess.run(["gsettings", "set", "org.gnome.system.proxy.socks", "host", host], check=True)
        subprocess.run(["gsettings", "set", "org.gnome.system.proxy.socks", "port", str(port)], check=True)
        print(f"GNOME system proxy set to {host}:{port}.")
    else:
        print(f"SOCKS proxy available at {host}:{port} - point your browser/apps at it.")


def clear_proxy():
    if plat.current_os() == "windows":
        import winreg
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, _WIN_REG_PATH, 0, winreg.KEY_SET_VALUE)
        winreg.SetValueEx(key, "ProxyEnable", 0, winreg.REG_DWORD, 0)
        winreg.CloseKey(key)
        print("System proxy cleared.")
    elif _gnome():
        subprocess.run(["gsettings", "set", "org.gnome.system.proxy", "mode", "none"], check=True)
        print("GNOME system proxy cleared.")
