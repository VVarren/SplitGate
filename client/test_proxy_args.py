import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).parent

def _run(args):
    return subprocess.run(
        [sys.executable, 'proxy.py'] + args,
        capture_output=True, text=True,
        cwd=HERE
    )

def test_no_args_prints_usage_and_exits_1():
    r = _run([])
    assert r.returncode == 1
    assert 'Usage' in r.stderr

def test_unknown_command_prints_usage_and_exits_1():
    r = _run(['foo'])
    assert r.returncode == 1
    assert 'Usage' in r.stderr
