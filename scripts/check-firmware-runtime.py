"""Verify the arm64 deployment target of every Mach-O in the shipped helper."""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from PyInstaller.archive.readers import CArchiveReader

helper = Path(sys.argv[1])
archive = CArchiveReader(str(helper))
# Both endiannesses, thin and universal Mach-O headers.
magic = {bytes.fromhex(h) for h in (
    "feedface", "feedfacf", "cafebabe", "cafebabf",
    "cefaedfe", "cffaedfe", "bebafeca", "bfbafeca",
)}
def check(path, name):
    output = subprocess.check_output(["otool", "-arch", "arm64", "-l", path], text=True)
    match = re.search(r"cmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform (?:1|MACOS)\s+minos ([\d.]+)", output, re.I)
    if not match:
        match = re.search(r"cmd LC_VERSION_MIN_MACOSX\s+cmdsize \d+\s+version ([\d.]+)", output)
    if not match or tuple(map(int, match[1].split("."))) > (13, 0, 0):
        sys.exit(f"{name}: unsupported arm64 minimum macOS ({match[1] if match else 'unknown'})")

check(helper, helper.name)
count = 0
with tempfile.TemporaryDirectory() as temp:
    binary = Path(temp) / "binary"
    for name in archive.toc:
        data = archive.extract(name)
        if data[:4] in magic:
            binary.write_bytes(data)
            check(binary, name)
            count += 1
if not count:
    sys.exit("No embedded native libraries found")
print(f"Verified macOS 13.0 deployment target or earlier for helper and {count} embedded binaries")
