from mojix.errno import Errno
from mojix.net.socket import socket, bind, listen
from mojix.net.types import AddrFamily, SocketType, SocketAddrV4
from mojix.timespec import Timespec
from io_uring import IoUring, WaitArg
from io_uring.op import Accept
from std.testing import assert_equal, assert_raises


def test_accept_timeout() raises:
    var ring = IoUring[](sq_entries=8)

    var fd = socket(AddrFamily.INET, SocketType.STREAM)
    bind(fd, SocketAddrV4(0, 0, 0, 0, port=1111))
    listen(fd, backlog=64)

    var sq = ring.sq()
    if sq:
        _ = Accept(sq.__next__(), fd)
    else:
        raise "no available sqes"

    assert_equal(ring.submit_and_wait(wait_nr=0), 1)

    var ts = Timespec(tv_sec=0, tv_nsec=100000000)
    with assert_raises(contains=String(Errno.ETIME)):
        _ = ring.cq(wait_nr=1, arg=WaitArg(ts).as_enter_arg())

    _ = fd^


def main() raises:
    test_accept_timeout()
