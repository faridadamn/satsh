import argparse
import os
import sys


def main():
    ap = argparse.ArgumentParser(prog="satsh")
    ap.add_argument("--port", type=int)
    ap.add_argument("--no-browser", action="store_true")
    a = ap.parse_args()
    if sys.version_info < (3, 8):
        print("satsh butuh Python 3.8+")
        sys.exit(1)
    from .config import HOME

    if sys.stdout is None or sys.stderr is None:  # pythonw.exe: no console
        log = open(os.path.join(HOME, "satsh.log"), "a", encoding="utf-8", buffering=1)
        sys.stdout = sys.stderr = log
    from .server import serve

    serve(a.port, open_browser=not a.no_browser)


if __name__ == "__main__":
    main()
