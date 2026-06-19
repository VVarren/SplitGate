from splitgate import cli


def test_no_args_returns_1_and_prints_usage(capsys):
    rc = cli.main([])
    assert rc == 1
    assert "Usage" in capsys.readouterr().err


def test_unknown_command_returns_1(capsys):
    rc = cli.main(["bogus"])
    assert rc == 1
    assert "Usage" in capsys.readouterr().err
