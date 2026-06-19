import sys

COMMANDS = {"on", "off", "status"}


def run(cmd):  # fully implemented in Task 7
    raise NotImplementedError(cmd)


def main(argv=None):
    if argv is None:
        argv = sys.argv[1:]
    if len(argv) != 1 or argv[0] not in COMMANDS:
        print(f"Usage: proxy <{' | '.join(sorted(COMMANDS))}>", file=sys.stderr)
        return 1
    return run(argv[0])
