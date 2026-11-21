#!/usr/bin/env python3
"""Offline check of two independently captured, unencrypted 16 MiB factory images."""
import argparse
import hashlib
import os
from pathlib import Path

# Hashes of the stock 0.2.18 release files, not of user data.
STOCK = (
    (0, 20912, "ef357d11230d3856f7b906eb13457f33e13831a5d92dbfa8191affa723121024"),
    (0x8000, 3072, "2be4d432f4b4a5ffed358d8bd7614a4aae17c171b205e57feb6e61352e317f95"),
    (0x20000, 890416, "64ecb613e279df28bb28ca7873851ebb2234c7f7f547531967c6aab262c77815"),
)

def verify(first, second):
    if os.path.samefile(first, second):
        raise ValueError("Supply two separate ROM readbacks.")
    data = first.read_bytes()
    if len(data) != 16 * 1024 * 1024 or data != second.read_bytes():
        raise ValueError("Readbacks differ or do not cover the entire flash.")
    for offset, length, expected in STOCK:
        if hashlib.sha256(data[offset:offset+length]).hexdigest() != expected:
            raise ValueError(f"Stock image mismatch at {offset:#x}. Stop and review the device layout.")
    return hashlib.sha256(data).hexdigest()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("first", type=Path)
    parser.add_argument("second", type=Path)
    args = parser.parse_args()
    try:
        print("Matching full flash images, SHA-256", verify(args.first, args.second))
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")
