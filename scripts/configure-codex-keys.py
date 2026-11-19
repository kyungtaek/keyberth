"""Provision missing desktop shortcuts for Codex Micro commands."""
import json
import os
from pathlib import Path
import tempfile


def configure(path):
    original = path.read_bytes() if path.exists() else None
    entries = json.loads(original) if original else []
    if not isinstance(entries, list) or not all(isinstance(row, dict) for row in entries):
        raise ValueError("Unrecognized Codex keybindings format")
    additions = []
    for command, letter in [("composer.toggleFastMode", "F"), ("forkThread", "B"), ("composer.togglePlanMode", "P"), ("approval.approve", "Y"), ("approval.decline", "N")]:
        if any(row.get("command") == command for row in entries):
            continue
        key = "Command+Control+Shift+" + letter
        if any(str(row.get("key")).lower() == key.lower() for row in entries):
            raise ValueError("Shortcut already assigned: " + key)
        additions.append({"command": command, "key": key})
        default = {"approval.approve": "Enter", "approval.decline": "Escape"}.get(command)
        if default:
            additions.append({"command": command, "key": default})
    if additions:
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as f:
            temp = Path(f.name)
            f.write((json.dumps(entries + additions, indent=2) + "\n").encode())
        try:
            if (path.read_bytes() if path.exists() else None) != original:
                raise RuntimeError("Codex keybindings changed during setup")
            os.replace(temp, path)
        finally:
            temp.unlink(missing_ok=True)
    return len(additions)


if __name__ == "__main__":
    print(configure(Path.home() / ".codex/keybindings.json"), "shortcuts added")
