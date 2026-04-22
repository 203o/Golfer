#!/usr/bin/env python3
"""
Lightweight client-bundle secret scan.
Fails fast on high-confidence secret leaks and forbidden asset packaging.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

SCAN_DIRS = [
    ROOT / "lib",
    ROOT / "android",
    ROOT / "ios",
    ROOT / "web",
]

SCAN_EXT = {".dart", ".kt", ".kts", ".gradle", ".xml", ".json", ".yaml", ".yml", ".plist"}

ALLOWLIST = {
    str((ROOT / "lib" / "firebase_options.dart").as_posix()),
    str((ROOT / "android" / "app" / "google-services.json").as_posix()),
    str((ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml").as_posix()),
}

RULES = [
    ("private_key_block", re.compile(r"-----BEGIN (?:RSA |EC )?PRIVATE KEY-----")),
    ("hardcoded_bearer", re.compile(r"Authorization\\s*[:=]\\s*['\"]Bearer\\s+[A-Za-z0-9\\-_.]{20,}")),
    ("daraja_secret_literal", re.compile(r"DARAJA_(?:CONSUMER_SECRET|PASSKEY)\\s*[:=]\\s*['\"][^'\"]{8,}['\"]")),
    ("service_account_private_key", re.compile(r'"private_key"\\s*:\\s*"-----BEGIN PRIVATE KEY-----')),
]

FORBIDDEN_ASSET_PATTERNS = [
    re.compile(r"^\\s*-\\s*\\.env\\s*$"),
    re.compile(r"^\\s*-\\s*credentials/firebase-service-account-key\\.json\\s*$"),
]


def iter_files():
    for base in SCAN_DIRS:
        if not base.exists():
            continue
        for p in base.rglob("*"):
            if not p.is_file():
                continue
            if p.suffix.lower() not in SCAN_EXT:
                continue
            yield p


def main() -> int:
    failures: list[str] = []

    pubspec = ROOT / "pubspec.yaml"
    if pubspec.exists():
        for i, line in enumerate(pubspec.read_text(encoding="utf-8", errors="ignore").splitlines(), start=1):
            for pat in FORBIDDEN_ASSET_PATTERNS:
                if pat.search(line):
                    failures.append(f"pubspec.yaml:{i} forbidden asset entry: {line.strip()}")

    for file in iter_files():
        path_posix = file.as_posix()
        text = file.read_text(encoding="utf-8", errors="ignore")
        if path_posix in ALLOWLIST:
            continue
        for rule_name, pattern in RULES:
            if pattern.search(text):
                failures.append(f"{path_posix}: matched rule `{rule_name}`")

    if failures:
        print("Security scan failed:")
        for f in failures:
            print(f"- {f}")
        return 1

    print("Security scan passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
