"""Reproduce read-only research checks. Never runs a core or modifies OS networking."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "core-example" / "vp_core"
EXPECTED_COMMIT = "fa3e7430371930c440ffb1bdccc6869c63554a34"


def check_documents() -> None:
    count = 0
    for path in sorted((ROOT / "docs").rglob("*.md")):
        body = path.read_text(encoding="utf-8")
        if body.count("```") % 2:
            raise RuntimeError(f"Unbalanced code fence: {path}")
        for target in re.findall(r"\]\(([^)]+)\)", body):
            target = target.strip("<>").split("#", 1)[0]
            if not target or re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target):
                continue
            if not (path.parent / unquote(target)).exists():
                raise RuntimeError(f"Broken local link: {path}: {target}")
            count += 1
    print(f"PASS: local Markdown links ({count}) and code fences", flush=True)


def run(command: list[str], expected: int = 0) -> None:
    print("RUN: " + " ".join(command), flush=True)
    result = subprocess.run(command, cwd=CORE, check=False)
    if result.returncode != expected:
        raise RuntimeError(f"Expected exit {expected}, got {result.returncode}")


def check_core() -> None:
    if not (CORE / "Cargo.lock").is_file():
        raise RuntimeError("Fetch the pinned vp_core checkout at core-example/vp_core first")
    commit = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=CORE, text=True
    ).strip()
    if commit != EXPECTED_COMMIT:
        raise RuntimeError(f"Core commit differs from documented baseline: {commit}")
    changes = subprocess.check_output(
        ["git", "status", "--porcelain", "--untracked-files=no"], cwd=CORE, text=True
    ).strip()
    if changes:
        raise RuntimeError("Core checkout has tracked modifications; use the documented baseline")
    # These tests use parser/rule logic, loopback listeners and an ordinary mixed
    # listener. They do not request a TUN or invoke the CLI shutdown/route cleaner.
    for packages, filters in [
        (["-p", "vp-config", "-p", "vp-rule"], []),
        (["-p", "vp-app"], ["api::tests"]),
        (["-p", "vp-ffi"], []),
    ]:
        run(["cargo", "test", "--locked", *packages, "--lib", *filters,
             "--", "--test-threads=1"])
    run(["cargo", "build", "--locked", "-p", "vp-bin"])
    target = os.environ.get("CARGO_TARGET_DIR")
    target_dir = Path(target) if target else CORE / "target"
    if not target_dir.is_absolute():
        target_dir = CORE / target_dir
    executable = target_dir / "debug" / ("vpcore.exe" if os.name == "nt" else "vpcore")
    examples = ROOT / "docs" / "examples"
    cases = [
        ("minimal.yaml", 0),
        ("rules.yaml", 0),
        ("android-template.yaml", 0),
        ("providers.yaml", 0),
        ("invalid-reference.yaml", 1),
        ("limitations/unknown-field.yaml", 0),
        ("limitations/unknown-rule.yaml", 0),
        ("limitations/overflow-port.yaml", 0),
    ]
    for name, expected in cases:
        run([str(executable), "validate", "-c", str(examples / name)], expected)
    print(f"PASS: {len(cases)} configuration validation expectations", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--docs-only", action="store_true")
    args = parser.parse_args()
    check_documents()
    if not args.docs_only:
        check_core()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
