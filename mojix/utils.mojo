from std.bit import byte_swap
from std.sys.info import align_of, Endian, size_of
from linux_raw.utils import DTypeArray


@always_inline("nodebug")
def _aligned_u64[T: AnyType]():
    # [Linux]: https://github.com/torvalds/linux/blob/v6.7/include/uapi/linux/types.h#L47.
    comptime assert align_of[T]() >= 8


@always_inline("nodebug")
def _size_eq[T: AnyType, I: AnyType]():
    comptime assert size_of[T]() == size_of[I]()


@always_inline("nodebug")
def _size_eq[T: AnyType, size: Int]():
    comptime assert size_of[T]() == size


@always_inline("nodebug")
def _align_eq[T: AnyType, I: AnyType]():
    comptime assert align_of[T]() == align_of[I]()


@always_inline("nodebug")
def _align_eq[T: AnyType, align: Int]():
    comptime assert align_of[T]() == align


@always_inline("nodebug")
def _to_be[
    type: DType, size: SIMDLength, //
](value: SIMD[type, size]) -> SIMD[type, size]:
    comptime if Endian.native() == .big:
        return value
    else:
        return byte_swap(value)
