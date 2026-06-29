#!/usr/bin/env python3
"""Extract agent models from CS:GO / CS:GO Legacy pak01_dir.vpk."""

from __future__ import annotations

import argparse
import os
import sys
import tarfile
import tempfile
from pathlib import Path

PREFIXES = (
    "models/player/custom_player/",
    "materials/models/player/custom_player/",
)


def find_pak_dir(csgo_dir: Path) -> Path | None:
    pak = csgo_dir / "pak01_dir.vpk"
    if pak.is_file():
        return pak
    return None


def find_csgo_dirs() -> list[Path]:
    roots: list[Path] = []
    if os.name == "nt":
        steam = Path(os.environ.get("PROGRAMFILES(X86)", "C:/Program Files (x86)")) / "Steam/steamapps/common"
        for game in (
            "csgo legacy/csgo",
            "Counter-Strike Global Offensive/csgo",
            "Counter-Strike Global Offensive Beta/csgo",
        ):
            roots.append(steam / game)
    else:
        home = Path.home()
        for base in (
            home / ".steam/steam/steamapps/common",
            home / ".local/share/Steam/steamapps/common",
        ):
            for game in ("csgo legacy/csgo", "Counter-Strike Global Offensive/csgo"):
                roots.append(base / game)
    return [p for p in roots if find_pak_dir(p)]


def extract_from_vpk(pak_path: Path, out_csgo: Path) -> tuple[int, int]:
    try:
        import vpk
    except ImportError:
        print("ERROR: pip install vpk", file=sys.stderr)
        sys.exit(1)

    archive = vpk.open(str(pak_path))
    models = 0
    materials = 0
    for name in archive:
        if not any(name.startswith(p) for p in PREFIXES):
            continue
        dest = out_csgo / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(archive[name].read())
        if name.startswith("models/"):
            models += 1
        else:
            materials += 1
    return models, materials


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract custom_player from CS:GO VPK")
    parser.add_argument("--csgo-dir", type=Path, help="Path to csgo/ (contains pak01_dir.vpk)")
    parser.add_argument(
        "--output-tarball",
        type=Path,
        default=Path(tempfile.gettempdir()) / "custom_player.tgz",
        help="Write tarball for VPS upload",
    )
    parser.add_argument("--extract-only", type=Path, help="Extract loose files to this csgo/ dir")
    args = parser.parse_args()

    csgo_dir = args.csgo_dir
    if csgo_dir is None:
        candidates = find_csgo_dirs()
        if not candidates:
            print("ERROR: no CS:GO install with pak01_dir.vpk found", file=sys.stderr)
            sys.exit(1)
        csgo_dir = candidates[0]
        print(f"Using: {csgo_dir}")

    pak = find_pak_dir(csgo_dir)
    if pak is None:
        print(f"ERROR: pak01_dir.vpk not found under {csgo_dir}", file=sys.stderr)
        sys.exit(1)

    if args.extract_only:
        out = args.extract_only
        out.mkdir(parents=True, exist_ok=True)
        models, materials = extract_from_vpk(pak, out)
        print(f"OK: extracted {models} model files, {materials} material files -> {out}")
        return

    with tempfile.TemporaryDirectory() as tmp:
        staging = Path(tmp) / "csgo"
        models, materials = extract_from_vpk(pak, staging)
        if models == 0:
            print("ERROR: no models/player/custom_player in VPK", file=sys.stderr)
            sys.exit(1)
        args.output_tarball.parent.mkdir(parents=True, exist_ok=True)
        with tarfile.open(args.output_tarball, "w:gz") as tar:
            for prefix in ("models", "materials"):
                src = staging / prefix
                if src.exists():
                    tar.add(src, arcname=prefix)
        print(f"OK: tarball {args.output_tarball} ({models} models, {materials} materials)")


if __name__ == "__main__":
    main()
