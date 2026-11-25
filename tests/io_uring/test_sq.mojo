from io_uring.mm import Region
from io_uring.modes import NOPOLL
from io_uring.sq import Sq, SqPtr
from mojix.io_uring import IoUringParams, SQE64
from mojix.mm import MapFlags
from std.testing import assert_equal, assert_false, assert_true


def test_sq_flush_and_retry() raises:
    comptime capacity = 4
    var params = IoUringParams()
    params.sq_entries = capacity
    params.sq_off.head = 0
    params.sq_off.tail = 4
    params.sq_off.ring_mask = 8
    params.sq_off.ring_entries = 12
    params.sq_off.flags = 16
    params.sq_off.dropped = 20
    params.sq_off.array = 24

    var ring_mem = Region.private(len=24 + 4 * capacity, flags=MapFlags())
    var sqes_mem = Region.private(
        len=UInt(capacity * SQE64.size), flags=MapFlags()
    )
    var kernel_head = ring_mem.unsafe_ptr[UInt32](offset=0, count=1)
    var published_tail = ring_mem.unsafe_ptr[UInt32](offset=4, count=1)
    kernel_head[] = UInt32.MAX - 1
    published_tail[] = kernel_head[]
    ring_mem.unsafe_ptr[UInt32](offset=8, count=1)[] = capacity - 1
    ring_mem.unsafe_ptr[UInt32](offset=12, count=1)[] = capacity

    var queue = Sq[SQE64, NOPOLL](params, sq_cq_mem=ring_mem, sqes_mem=sqes_mem)
    var sq = SqPtr(queue)
    assert_equal(len(sq), capacity)
    for _ in range(capacity):
        _ = sq.__next__()
    assert_equal(published_tail[], UInt32.MAX - 1)

    # Publish a full queue across UInt32 wraparound. An interrupted enter
    # can leave the kernel head unchanged, including on a retry.
    assert_equal(queue.flush(), capacity)
    assert_equal(published_tail[], 2)
    assert_equal(len(SqPtr(queue)), 0)
    assert_false(SqPtr(queue))
    queue.sync_head()
    assert_equal(len(SqPtr(queue)), 0)
    assert_equal(queue.flush(), capacity)

    # The kernel consumes two entries. The unsynced view stays conservative
    # until the head is refreshed.
    kernel_head[] = 0
    assert_equal(len(SqPtr(queue)), 0)
    queue.sync_head()
    sq = SqPtr(queue)
    assert_equal(len(sq), 2)
    assert_true(sq)
    assert_equal(queue.flush(), 2)
    assert_equal(published_tail[], 2)

    # Refill the first reusable slot and retry with both old and new entries.
    sq = SqPtr(queue)
    sq.__next__().user_data = 42
    assert_equal(queue.sqes[unsafe_offset=2].user_data, 42)
    assert_equal(published_tail[], 2)
    assert_equal(queue.flush(), 3)
    assert_equal(published_tail[], 3)
    assert_equal(len(SqPtr(queue)), 1)
    assert_equal(queue.flush(), 3)

    kernel_head[] = 3
    assert_equal(queue.flush(), 0)
    assert_equal(len(SqPtr(queue)), capacity)
    assert_equal(published_tail[], 3)

    # Keep the mappings alive while queue and the simulated kernel use them.
    _ = ring_mem
    _ = sqes_mem


def main() raises:
    test_sq_flush_and_retry()
