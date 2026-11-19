"""Pure policy for T3 Code v0.1.7 exact local web links. No I/O."""
import ipaddress
import re
from urllib.parse import urlsplit, urlunsplit

_VERSION = "0.1.7"
_ID = re.compile(r"[A-Za-z0-9_-]{1,128}", re.ASCII)


def thread_url(version, loopback_origin, environment_id, thread_id):
    """Return a local chooser/redirect URL for a manually connected browser only."""
    if version != _VERSION or not all(
        isinstance(i, str) and _ID.fullmatch(i) for i in (environment_id, thread_id)
    ):
        raise ValueError("Unsupported version or identifiers")
    if not isinstance(loopback_origin, str) or re.search(r"[\x00-\x20\x7f\\]", loopback_origin):
        raise ValueError("Expected literal loopback origin")
    parsed = urlsplit(loopback_origin)
    if (parsed.scheme not in {"http", "https"} or parsed.username is not None
            or parsed.password is not None or parsed.path not in {"", "/"}
            or "?" in loopback_origin or "#" in loopback_origin or not parsed.port):
        raise ValueError("Expected literal loopback origin with explicit port")
    if parsed.hostname not in {"127.0.0.1", "::1"} or not ipaddress.ip_address(parsed.hostname).is_loopback:
        raise ValueError("Only literal loopback is allowed")
    authority = f"[::1]:{parsed.port}" if parsed.hostname == "::1" else f"127.0.0.1:{parsed.port}"
    if parsed.netloc != authority:
        raise ValueError("Noncanonical authority")
    return urlunsplit((parsed.scheme, authority, f"/threads/{environment_id}/{thread_id}", "", ""))


def native_thread_url(version, environment_id, thread_id):
    """Build the stock 0.1.7 native navigation URL. Never opens anything."""
    if version != _VERSION or not all(
        isinstance(i, str) and _ID.fullmatch(i) for i in (environment_id, thread_id)
    ):
        raise ValueError("Unsupported version or identifiers")
    return f"t3code://threads/{environment_id}/{thread_id}"
