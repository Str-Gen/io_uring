from mojix.io_uring import IoUringCqeFlags
from io_uring import IoUring
from io_uring.buf import BufRing
from std.testing import assert_equal


def test_flags_to_index() raises:
    var flags = IoUringCqeFlags(2298576896)
    var index = BufRing.flags_to_index(flags)
    assert_equal(index, 35073)


def test_buf_into_index[is_registered: Bool]() raises:
    var ring = IoUring[is_registered=is_registered](sq_entries=16)
    var buf_ring = ring.create_buf_ring(bgid=0, entries=128, entry_size=1024)
    assert_equal(buf_ring._tail, 128)

    var buf_ring_ptr = buf_ring[]
    var buf = buf_ring_ptr.unsafe_buf(flags=IoUringCqeFlags(0), len=1024)
    var index = buf^.into_index()
    assert_equal(index, 0)

    assert_equal(buf_ring._tail, 128)
    ring.unsafe_delete_buf_ring(buf_ring^)


def main() raises:
    test_flags_to_index()
    test_buf_into_index[False]()
    test_buf_into_index[True]()
