"""Where Reserve keeps its history, and the only code that touches those files.

Everything lives in $XDG_STATE_HOME/reserve (by default ~/.local/state/reserve), a directory of its own made 0700.
Files are opened relative to that directory's descriptor and never through a symbolic link, must be regular files
the user owns, and are read with a ceiling, so a planted link or a runaway file cannot redirect or exhaust anything.
"""
from __future__ import annotations

import datetime as dt
import fcntl
import json
import os
import re
import stat

DAY_MAX = 8 * 1024 * 1024       # one day's file: a sample line is ~60 bytes, a bucket ~400, so this is far above use
HEALTH_MAX = 1024 * 1024
DATED = re.compile(r"^(\d{4})-(\d{2})(?:-(\d{2}))?\.jsonl$")


class Unsafe(Exception):
    pass


def state_root() -> str:
    base = os.environ.get("XDG_STATE_HOME", "")
    if not base.startswith("/"):
        base = os.path.join(os.path.expanduser("~"), ".local", "state")
    return os.path.join(base, "reserve")


def _own_dir(path: str, create: bool) -> int:
    """A descriptor for `path`, a directory the user owns and nobody else can write; made 0700 when missing."""
    if create:
        try:
            os.mkdir(path, 0o700)
        except FileExistsError:
            pass
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
    info = os.fstat(fd)
    if info.st_uid != os.getuid() or info.st_mode & 0o022:
        os.close(fd)
        raise Unsafe(f"{path}: not a private directory of ours")
    return fd


def dir_fd(*parts: str, create: bool = True) -> int:
    root = state_root()
    if create:
        os.makedirs(os.path.dirname(root), exist_ok=True)
    fd = _own_dir(root, create)
    for part in parts:
        try:
            if create:
                try:
                    os.mkdir(part, 0o700, dir_fd=fd)
                except FileExistsError:
                    pass
            nfd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=fd)
        finally:
            os.close(fd)
        info = os.fstat(nfd)
        if info.st_uid != os.getuid() or info.st_mode & 0o022:
            os.close(nfd)
            raise Unsafe(f"{part}: not a private directory of ours")
        fd = nfd
    return fd


def append(sub: str, name: str, record) -> None:
    """One JSON line onto a file in a subdirectory, created 0600; never through a link, never past the ceiling."""
    line = (json.dumps(record, separators=(",", ":"), ensure_ascii=True) + "\n").encode("ascii")
    d = dir_fd(sub)
    try:
        fd = os.open(name, os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600, dir_fd=d)
    finally:
        os.close(d)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
            raise Unsafe(f"{sub}/{name}: not a regular file of ours")
        if info.st_size + len(line) > DAY_MAX:
            return
        os.write(fd, line)
    finally:
        os.close(fd)


def read_lines(sub: str, name: str, ceiling: int = DAY_MAX) -> list:
    """Every JSON line of a file that parses; a missing file is no lines."""
    try:
        d = dir_fd(sub, create=False)
    except (OSError, Unsafe):
        return []
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=d)
    except OSError:
        return []
    finally:
        os.close(d)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
            return []
        raw = os.read(fd, ceiling) if info.st_size <= ceiling else b""
    finally:
        os.close(fd)
    out = []
    for line in raw.decode("utf-8", "replace").splitlines():
        try:
            out.append(json.loads(line))
        except ValueError:
            continue
    return out


def day_name(t: float) -> str:
    return dt.datetime.fromtimestamp(t).strftime("%Y-%m-%d") + ".jsonl"


def month_name(t: float) -> str:
    return dt.datetime.fromtimestamp(t).strftime("%Y-%m") + ".jsonl"


def prune(sub: str, keep_days: int, today: dt.date) -> int:
    """Remove dated files older than `keep_days` (by the date in their name). Answers how many went."""
    try:
        d = dir_fd(sub, create=False)
    except (OSError, Unsafe):
        return 0
    gone = 0
    try:
        for name in os.listdir(d):
            m = DATED.match(name)
            if not m:
                continue
            y, mo, da = int(m.group(1)), int(m.group(2)), int(m.group(3) or 28)
            try:
                when = dt.date(y, mo, da)
            except ValueError:
                continue
            if (today - when).days > keep_days:
                info = os.stat(name, dir_fd=d, follow_symlinks=False)
                if stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid():
                    os.unlink(name, dir_fd=d)
                    gone += 1
    finally:
        os.close(d)
    return gone


def single_instance():
    """A lock only one sampler holds: a second one started by a shell reload exits at once."""
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    if not runtime.startswith("/"):
        runtime = state_root()
    fd = os.open(os.path.join(runtime, "reserve.lock"), os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        os.close(fd)
        return None
    return fd
