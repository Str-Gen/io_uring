from std.io.file import FileHandle
from std.memory import Pointer
from std.tempfile import TemporaryDirectory
from std.testing import assert_equal

from io_uring import IoUring
from io_uring.op import Read
from mojix.fd import Fd


def check_reads(mut file: FileHandle, mut first: Int8, mut last: Int16) raises:
    var fd = Fd(unsafe_fd=Int32(file.handle))
    var ring = IoUring[](sq_entries=4)
    var sq = ring.sq()
    # The first request spans EOF. Its unused byte should remain zero.
    _ = (
        Read(sq.__next__(), fd, Pointer(to=last).unsafe_bitcast[Int8](), 2)
        .offset(5)
        .user_data(2)
    )
    _ = Read(sq.__next__(), fd, Pointer(to=first), 1).offset(1).user_data(1)
    assert_equal(ring.submit_and_wait(wait_nr=2), 2)
    var seen: UInt64 = 0
    for cqe in ring.cq(wait_nr=0):
        assert_equal(cqe.res, 1)
        assert_equal(seen & cqe.user_data, 0)
        seen |= cqe.user_data
    assert_equal(seen, 3)
    assert_equal(file.seek(0, 1), 0)


def main() raises:
    with TemporaryDirectory() as directory:
        var path = directory + "/offsets.bin"
        with open(path, "w") as writer:
            writer.write("abcdef")
        with open(path, "r") as reader:
            var first: Int8 = 0
            var last: Int16 = 0
            check_reads(reader, first, last)
            assert_equal(first, 98)
            assert_equal(last, 102)
