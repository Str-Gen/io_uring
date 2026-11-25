from mojix.errno import Errno
from mojix.io_uring import IoUringSetupFlags
from mojix.timespec import Timespec
from io_uring import IoUring, Params, WaitArg
from io_uring.op import Nop
from std.testing import assert_equal, assert_false, assert_raises, assert_true


@fieldwise_init
struct OpQueue(TrivialRegisterPassable):
    var size: UInt

    @always_inline
    def __bool__(self) -> Bool:
        return self.size != 0

    @always_inline
    def pop(mut self):
        self.size -= 1


def test_nop_no_sq_array() raises:
    var params = Params()
    params.flags = IoUringSetupFlags.NO_SQARRAY
    var ring = IoUring[is_registered=False](sq_entries=16, params=params)
    assert_false(ring._sq.array)
    var queue = OpQueue(128)
    var total: UInt32 = 0

    while queue:
        var to_submit: UInt32 = 0
        var sq = ring.sq()
        while queue and sq:
            _ = Nop(sq.__next__()).user_data(1)
            queue.pop()
            to_submit += 1

        assert_equal(to_submit, 16)
        _ = ring.submit_and_wait(wait_nr=to_submit)
        var completed: UInt32 = 0
        for cqe in ring.cq(wait_nr=0):
            assert_equal(cqe.user_data, 1)
            completed += 1
        assert_equal(completed, to_submit)
        total += to_submit

    assert_equal(total, 128)


def test_default_depth_128() raises:
    comptime depth = 128
    var ring = IoUring[](sq_entries=depth)
    assert_true(ring._sq.array)

    for batch in range(2):
        var first_tag = batch * depth
        var sq = ring.sq()
        assert_equal(len(sq), depth)
        for i in range(depth):
            _ = Nop(sq.__next__()).user_data(UInt64(first_tag + i))

        assert_equal(ring.submit_and_wait(wait_nr=depth), depth)
        var seen = List[Bool](length=depth, fill=False)
        var completed = 0
        for cqe in ring.cq(wait_nr=0):
            assert_equal(cqe.res, 0)
            var index = Int(cqe.user_data) - first_tag
            assert_true(0 <= index < depth)
            assert_false(seen[index])
            seen[index] = True
            completed += 1
        assert_equal(completed, depth)


def test_nop_skip_cqe() raises:
    var ring = IoUring[](sq_entries=8)
    var count: UInt32 = 0
    for _sqe in ring.sq():
        count += 1
    assert_equal(count, 8)
    assert_equal(ring.submit_and_wait(wait_nr=0), count)

    var ts = Timespec(tv_sec=0, tv_nsec=100000000)
    # We expect a timeout and 0 cqes because none of the submitted sqes were
    # configured to perform any operation.
    with assert_raises(contains=String(Errno.ETIME)):
        _ = ring.cq(wait_nr=1, arg=WaitArg(ts).as_enter_arg())


def test_cq_wait_with_partially_ready_queue() raises:
    var ring = IoUring[](sq_entries=1)

    # The CQ holds two entries. The third completion stays in overflow until
    # there is room and the kernel flushes it.
    for user_data in range(3):
        var sq = ring.sq()
        _ = Nop(sq.__next__()).user_data(UInt64(user_data))
        assert_equal(ring.submit_and_wait(wait_nr=0), 1)

    for cqe in ring.cq(wait_nr=0):
        assert_equal(cqe.user_data, 0)
        break

    assert_equal(len(ring.cq(wait_nr=0)), 1)
    var timeout = Timespec(tv_sec=0, tv_nsec=100_000_000)
    assert_equal(
        len(ring.cq(wait_nr=1, arg=WaitArg(timeout).as_enter_arg())), 1
    )
    var cq = ring.cq(wait_nr=2, arg=WaitArg(timeout).as_enter_arg())
    assert_equal(len(cq), 2)
    assert_equal(cq.__next__().user_data, 1)
    assert_equal(cq.__next__().user_data, 2)


def test_cq_timeout_with_partially_ready_queue() raises:
    var ring = IoUring[](sq_entries=1)
    var sq = ring.sq()
    _ = Nop(sq.__next__()).user_data(1)
    assert_equal(ring.submit_and_wait(wait_nr=0), 1)
    assert_equal(len(ring.cq(wait_nr=0)), 1)

    # On timeout the kernel returns success if a completion is available.
    var timeout = Timespec(tv_sec=0, tv_nsec=100_000_000)
    var cq = ring.cq(wait_nr=2, arg=WaitArg(timeout).as_enter_arg())
    assert_equal(len(cq), 1)
    assert_equal(cq.__next__().user_data, 1)


def main() raises:
    test_nop_no_sq_array()
    test_default_depth_128()
    test_nop_skip_cqe()
    test_cq_wait_with_partially_ready_queue()
    test_cq_timeout_with_partially_ready_queue()
