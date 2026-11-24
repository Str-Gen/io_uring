from mojix.io_uring import (
    IoUringParams,
    io_uring_setup,
    io_uring_register,
    io_uring_enter,
    CQE_SIZE_DEFAULT,
    IoUringSetupFlags,
    IoUringEnterFlags,
    NoRegisterArg,
    NO_ENTER_ARG,
)
from mojix.fd import IoUringFileDescriptor
from mojix.errno import Errno
from std.testing import *


def _io_uring_enter_get_events[
    Fd: IoUringFileDescriptor
](fd: Fd) raises -> UInt32:
    return io_uring_enter(
        fd,
        to_submit=0,
        min_complete=0,
        flags=IoUringEnterFlags.GETEVENTS,
        arg=NO_ENTER_ARG,
    )


def _test_io_uring_setup[*, use_sq_array: Bool]() raises:
    var params = IoUringParams()

    comptime if not use_sq_array:
        params.flags = IoUringSetupFlags.NO_SQARRAY

    _ = io_uring_setup[is_registered=False](16, params)
    assert_equal(params.sq_entries, 16)
    assert_equal(params.cq_entries, 32)

    comptime if use_sq_array:
        assert_false(params.flags)
    else:
        assert_true(params.flags & IoUringSetupFlags.NO_SQARRAY)
    assert_equal(params.sq_thread_cpu, 0)
    assert_equal(params.sq_thread_idle, 0)
    assert_equal(params.wq_fd, 0)
    assert_equal(params.sq_off.head, 0)
    assert_equal(params.sq_off.tail, 4)
    assert_equal(params.cq_off.head, 8)
    assert_equal(params.cq_off.tail, 12)
    assert_equal(params.sq_off.ring_mask, 16)
    assert_equal(params.cq_off.ring_mask, 20)
    assert_equal(params.sq_off.ring_entries, 24)
    assert_equal(params.cq_off.ring_entries, 28)
    assert_equal(params.sq_off.dropped, 32)
    assert_equal(params.sq_off.flags, 36)
    assert_equal(params.cq_off.flags, 40)
    assert_equal(params.cq_off.overflow, 44)
    assert_equal(params.cq_off.cqes, 64)

    comptime if use_sq_array:
        assert_equal(
            params.sq_off.array,
            params.cq_off.cqes + params.cq_entries * UInt32(CQE_SIZE_DEFAULT),
        )
    else:
        assert_equal(params.sq_off.array, 0)


def test_io_uring_register_enable_rings_error() raises:
    var params = IoUringParams()
    var fd = io_uring_setup[is_registered=False](16, params)
    with assert_raises(contains=String(Errno.EBADFD)):
        _ = io_uring_register(fd, NoRegisterArg.ENABLE_RINGS)


def test_io_uring_setup() raises:
    _test_io_uring_setup[use_sq_array=True]()


def test_io_uring_setup_no_sq_array() raises:
    _test_io_uring_setup[use_sq_array=False]()


def test_io_uring_enter() raises:
    var params = IoUringParams()
    var fd = io_uring_setup[is_registered=False](16, params)
    assert_equal(_io_uring_enter_get_events(fd), 0)


def main() raises:
    test_io_uring_register_enable_rings_error()
    test_io_uring_setup()
    test_io_uring_setup_no_sq_array()
    test_io_uring_enter()
