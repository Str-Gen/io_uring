from io_uring import CQE16, CQE32, SQE64, SQE128, IoUring, Params
from io_uring.modes import IOPOLL, NOPOLL
from mojix.io_uring import IoUringParams, IoUringSetupFlags
from std.testing import assert_equal, assert_raises


def test_incompatible_setup_flags() raises:
    # Exercise the shared validation step without constructing a ring.
    var incompatible: List[IoUringSetupFlags] = [
        .SQE128,
        .CQE32,
        .SQE_MIXED,
        .CQE_MIXED,
        .SQ_REWIND,
        .IOPOLL,
        .HYBRID_IOPOLL,
        .SQPOLL,
        .SQ_AFF,
    ]
    var params = Params()
    for flag in incompatible:
        with assert_raises(contains="setup flags incompatible with typed ring"):
            _ = IoUring[]._resolve_setup_flags(params.flags | flag)

    var raw = IoUringParams()
    raw.flags = IoUringSetupFlags.IOPOLL | IoUringSetupFlags.SQPOLL
    with assert_raises(contains="setup flags incompatible with typed ring"):
        _ = IoUring[SQE64, CQE16, IOPOLL]._resolve_setup_flags(raw.flags)


def test_default_setup_flags() raises:
    var params = Params()
    assert_equal(params.flags.value, 0)
    assert_equal(IoUring[]._resolve_setup_flags(params.flags).value, 0)


def test_unregistered_setup_flags() raises:
    comptime UnregisteredRing = IoUring[
        SQE64, CQE16, NOPOLL, is_registered=False
    ]
    var raw = IoUringParams()
    raw.flags = IoUringSetupFlags.NO_MMAP
    with assert_raises(contains="setup flags incompatible with typed ring"):
        _ = UnregisteredRing._resolve_setup_flags(raw.flags)
    raw.flags = IoUringSetupFlags.REGISTERED_FD_ONLY
    with assert_raises(contains="setup flags incompatible with typed ring"):
        _ = UnregisteredRing._resolve_setup_flags(raw.flags)

    var params = Params()
    _ = params.cq_entries(16).clamp()
    params.flags |= IoUringSetupFlags.SUBMIT_ALL | IoUringSetupFlags.NO_SQARRAY
    assert_equal(
        UnregisteredRing._resolve_setup_flags(params.flags).value,
        params.flags.value,
    )
    assert_equal(
        UnregisteredRing._resolve_setup_flags(IoUringSetupFlags()).value, 0
    )


def test_matching_setup_flags() raises:
    comptime Ring = IoUring[SQE128, CQE32, IOPOLL, is_registered=True]
    comptime registered = (
        IoUringSetupFlags.NO_MMAP | IoUringSetupFlags.REGISTERED_FD_ONLY
    )
    comptime required = (
        registered
        | IoUringSetupFlags.SQE128
        | IoUringSetupFlags.CQE32
        | IoUringSetupFlags.IOPOLL
    )

    var raw = IoUringParams()
    assert_equal(Ring._resolve_setup_flags(raw.flags).value, required.value)
    raw.flags = required | IoUringSetupFlags.HYBRID_IOPOLL
    assert_equal(Ring._resolve_setup_flags(raw.flags).value, raw.flags.value)

    var params = Params()
    params.flags |= IoUringSetupFlags.NO_MMAP | IoUringSetupFlags.NO_SQARRAY
    assert_equal(
        IoUring[is_registered=True]._resolve_setup_flags(params.flags).value,
        (params.flags | registered).value,
    )


def main() raises:
    test_incompatible_setup_flags()
    test_default_setup_flags()
    test_unregistered_setup_flags()
    test_matching_setup_flags()
