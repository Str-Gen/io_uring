from std.atomic import Atomic, Ordering as AtomicOrdering
from std.sys.intrinsics import llvm_intrinsic, unlikely
from std.sys.info import bit_width_of
from std.memory import Pointer


struct _AddOverflowResult(TrivialRegisterPassable):
    var value: UInt32
    var overflow: Bool


def _atomic_load[
    type: DType, //, ordering: AtomicOrdering
](ptr: Pointer[Scalar[type], MutUntrackedOrigin]) -> Scalar[type]:
    return Atomic[Scalar[type]].load[ordering=ordering](ptr)


def _atomic_store[
    type: DType, //
](ptr: Pointer[Scalar[type], MutUntrackedOrigin], rhs: Scalar[type]):
    Atomic[Scalar[type]].store[ordering=AtomicOrdering.RELEASE](ptr, rhs)


@always_inline("nodebug")
def _next_power_of_two(value: UInt32) -> UInt32:
    """Returns the smallest power of two greater than or equal
    to the input value.

    When the return value overflows, function panics if assertions are enabled,
    and the return value wraps to 0 otherwise (the only situation in which
    function can return 0).

    Args:
        value: The input value.

    Returns:
        The smallest power of two greater than or equal to the input value.
    """
    debug_assert(
        value <= (UInt32(1) << UInt32(bit_width_of[UInt32]() - 1)),
        "result overflow",
    )
    return _one_less_than_next_power_of_two(value) + 1


@always_inline("nodebug")
def _one_less_than_next_power_of_two(value: UInt32) -> UInt32:
    """Returns one less than the next power of two.

    Args:
        value: The input value.

    Returns:
        One less than the next power of two of the input value.

    This function cannot overflow, as in the `_next_power_of_two`
    overflow cases it instead ends up returning the maximum value
    of the type, and can return 0 for 0.
    """
    if value <= 1:
        return 0

    var p = value - 1
    # Because `p > 0`, it cannot consist entirely of leading zeros.
    # That means the shift is always in-bounds, and some processors
    # (such as Intel pre-Haswell) have more efficient ctlz
    # intrinsics when the argument is non-zero.
    var z = llvm_intrinsic["llvm.ctlz", UInt32, has_side_effect=False](p, True)
    return UInt32.MAX >> z


@always_inline("nodebug")
def _add_with_overflow(lhs: UInt32, rhs: UInt32) -> _AddOverflowResult:
    """Computes `lhs + rhs` and a `Bool` indicating overflow.

    Args:
        lhs: The lhs value.
        rhs: The rhs value.

    Returns:
        A struct with the results of the operation and a `Bool` indicating
        overflow.
    """
    return llvm_intrinsic[
        "llvm.uadd.with.overflow",
        _AddOverflowResult,
    ](lhs, rhs)


@always_inline("nodebug")
def _checked_add(lhs: UInt32, rhs: UInt32) raises -> UInt32:
    """Computes `lhs + rhs`.

    Args:
        lhs: The lhs value.
        rhs: The rhs value.

    Returns:
        `lhs + rhs` value.

    Raises:
        If an overflow occurs.
    """
    var res = _add_with_overflow(lhs, rhs)
    if unlikely(res.overflow):
        raise "integer overflow"
    return res.value
