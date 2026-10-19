"""Ponto de entrada do executável Windows (PyInstaller): PegaMidia.exe."""

import sys

from pegamidia_server.desktop import main

if __name__ == "__main__":
    sys.exit(main())
