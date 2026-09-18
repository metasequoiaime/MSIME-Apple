"""Shared Unix provider startup ownership and stale socket recovery."""
import errno
import fcntl
import os
import socket
import stat


def claim_socket(path):
    """Serialize startup and recover only an owned, unresponsive socket."""
    lock = os.open(str(path) + ".lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        info = os.fstat(lock)
        if info.st_uid != os.getuid() or not stat.S_ISREG(info.st_mode) or info.st_mode & 0o077:
            raise ValueError("invalid service lock")
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            before = path.lstat()
        except FileNotFoundError:
            return lock
        if before.st_uid != os.getuid() or not stat.S_ISSOCK(before.st_mode):
            raise ValueError("socket path is occupied")
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as probe:
            probe.settimeout(0.5)
            try:
                probe.connect(str(path))
            except OSError as error:
                if error.errno != errno.ECONNREFUSED:
                    raise ValueError("socket availability is unknown") from None
            else:
                raise ValueError("provider service is already running")
        after = path.lstat()
        if (before.st_dev, before.st_ino) != (after.st_dev, after.st_ino):
            raise ValueError("socket changed during startup")
        path.unlink()
        return lock
    except Exception:
        os.close(lock)
        raise

