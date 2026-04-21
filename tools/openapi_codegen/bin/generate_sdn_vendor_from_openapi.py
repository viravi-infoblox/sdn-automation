#!/usr/bin/env python3

from __future__ import annotations

import sys
from pathlib import Path


def _bootstrap() -> None:
    script_dir = Path(__file__).resolve().parent
    python_lib = script_dir.parent / "src" / "python"
    sys.path.insert(0, str(python_lib))


def main() -> int:
    _bootstrap()
    from netmri_sdn_openapi_codegen import main as codegen_main  # pyright: ignore[reportMissingImports]

    return codegen_main()


if __name__ == "__main__":
    raise SystemExit(main())