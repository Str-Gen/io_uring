from .qp import IoUring
from .mm import Region
from .utils import _atomic_store
from mojix.ctypes import c_void
from mojix.io_uring import (
    IoUringBufReg,
    IoUringCqeFlags,
    IoUringRegisterOp,
    io_uring_buf,
    IORING_CQE_BUFFER_SHIFT,
)
from mojix.mm import MapFlags
from mojix.utils import _size_eq, _align_eq
from std.sys.info import bit_width_of, size_of
from std.memory import Pointer


# TODO: mark as @explicit_destroy
struct BufRing:
    var _mem: Region
    var _tail_ptr: Pointer[UInt16, MutUntrackedOrigin]
    var _tail: UInt16
    var _mask: UInt16
    var _buf_ptr: Pointer[c_void, MutUntrackedOrigin]
    var entries: UInt16
    var entry_size: UInt32
    var bgid: UInt16

    # ===------------------------------------------------------------------=== #
    # Life cycle methods
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __init__(
        out self,
        io_uring: IoUring,
        *,
        bgid: UInt16,
        entries: UInt16,
        entry_size: UInt32,
    ) raises:
        _size_eq[io_uring_buf, 16]()
        _align_eq[io_uring_buf, 8]()
        var ring_size = (
            UInt(size_of[io_uring_buf]()) + UInt(entry_size)
        ) * UInt(entries)
        var mem = Region.private(len=ring_size, flags=MapFlags())

        var reg = IoUringBufReg(
            ring_addr=mem.addr(),
            ring_entries=UInt32(entries),
            bgid=bgid,
        )
        var res = io_uring.register(
            reg.as_register_arg(
                unsafe_opcode=IoUringRegisterOp.REGISTER_PBUF_RING
            )
        )
        debug_assert(res == 0, "failed to register buffer ring")

        self._mem = mem^

        var ring_ptr = self._mem.unsafe_mut_ptr[io_uring_buf]()
        # Init tail.
        # [liburing]: https://github.com/axboe/liburing/blob/liburing-2.6/src/include/liburing.h#L1444.
        ring_ptr[].resv = 0

        # Derive _tail_ptr and _buf_ptr via address arithmetic on self._mem.
        # These use MutUntrackedOrigin (writes go through _atomic_store).
        var mem_base = Int(self._mem.unsafe_ptr())
        self._tail_ptr = Pointer[UInt16, MutUntrackedOrigin](
            unsafe_from_address=mem_base + 14  # offset of resv in io_uring_buf
        )
        self._tail = self._tail_ptr[]
        self._mask = entries - 1
        self._buf_ptr = Pointer[c_void, MutUntrackedOrigin](
            unsafe_from_address=mem_base
            + size_of[io_uring_buf]() * Int(entries)
        )
        self.entries = entries
        self.entry_size = entry_size
        self.bgid = bgid

        var self_ptr = self[]
        for i in range(entries):
            self_ptr.unsafe_recycle[init=True](index=UInt16(i))

    @always_inline
    def unsafe_unregister(var self, io_uring: IoUring) raises:
        var reg = IoUringBufReg(
            ring_addr=0,
            ring_entries=0,
            bgid=self.bgid,
        )
        var res = io_uring.register(
            reg.as_register_arg(
                unsafe_opcode=IoUringRegisterOp.UNREGISTER_PBUF_RING
            )
        )
        debug_assert(res == 0, "failed to unregister buffer ring")

    @always_inline
    def __init__(out self, *, deinit move: Self):
        """Moves data of an existing BufRing into a new one.

        Args:
            move: The existing BufRing.
        """
        self._mem = move._mem^
        self._tail_ptr = move._tail_ptr
        self._tail = move._tail
        self._mask = move._mask
        self._buf_ptr = move._buf_ptr
        self.entries = move.entries
        self.entry_size = move.entry_size
        self.bgid = move.bgid

    # ===------------------------------------------------------------------===#
    # Operator dunders
    # ===------------------------------------------------------------------===#

    @always_inline
    def __getitem__(mut self) -> BufRingPtr[origin_of(self)]:
        """Enable subscript syntax `buf_ring[]` for mutable access to the buffer ring.

        Returns:
            Pointer to the mutable buffer ring.
        """
        return self

    # ===-------------------------------------------------------------------===#
    # Methods
    # ===-------------------------------------------------------------------===#

    @always_inline
    def sync_tail(self):
        _atomic_store(self._tail_ptr, self._tail)

    @always_inline
    @staticmethod
    def flags_to_index(flags: IoUringCqeFlags) -> UInt16:
        comptime assert (
            bit_width_of[IoUringCqeFlags]() - IORING_CQE_BUFFER_SHIFT
            <= bit_width_of[UInt16]()
        )
        return UInt16((flags >> IORING_CQE_BUFFER_SHIFT).value)


struct BufRingPtr[ring_origin: MutOrigin](RegisterPassable):
    var _ring: Pointer[BufRing, Self.ring_origin]

    # ===------------------------------------------------------------------=== #
    # Life cycle methods
    # ===------------------------------------------------------------------=== #

    @implicit
    @always_inline
    def __init__(out self, ref[Self.ring_origin] ring: BufRing):
        self._ring = Pointer(to=ring)

    @always_inline
    def __deinit__(deinit self):
        self._ring[].sync_tail()

    # ===-------------------------------------------------------------------===#
    # Methods
    # ===-------------------------------------------------------------------===#

    @always_inline
    def unsafe_buf[
        buf_origin: MutOrigin
    ](ref[buf_origin] self, *, index: UInt16, len: UInt32) -> Buf[
        buf_origin, Self.ring_origin
    ]:
        var buf_ptr = self._ring[]._buf_ptr.unsafe_offset(
            UInt(index) * UInt(self._ring[].entry_size)
        )
        return Buf(
            unsafe_buf_ptr=buf_ptr,
            len=len,
            index=index,
            ring_ptr=Pointer(to=self),
        )

    @always_inline
    def unsafe_buf[
        buf_origin: MutOrigin
    ](ref[buf_origin] self, *, flags: IoUringCqeFlags, len: UInt32) -> Buf[
        buf_origin, Self.ring_origin
    ]:
        return self.unsafe_buf(index=BufRing.flags_to_index(flags), len=len)

    @always_inline
    def unsafe_recycle[*, init: Bool = False](mut self, *, index: UInt16):
        var slot = (
            self._ring[]
            ._mem.unsafe_mut_ptr[io_uring_buf]()
            .unsafe_offset(self._ring[]._tail & self._ring[]._mask)
        )
        slot[].addr = UInt64(
            self._ring[]._buf_ptr.unsafe_offset(
                UInt(index) * UInt(self._ring[].entry_size)
            )
        )

        slot[].bid = index

        comptime if init:
            slot[].len = self._ring[].entry_size

        self._ring[]._tail += 1

    @always_inline
    def unsafe_recycle(mut self, *, flags: IoUringCqeFlags):
        self.unsafe_recycle(index=BufRing.flags_to_index(flags))


struct Buf[buf_origin: MutOrigin, ring_origin: MutOrigin](RegisterPassable):
    var buf_ptr: Pointer[c_void, MutUntrackedOrigin]
    var len: UInt32
    var index: UInt16
    var _ring_ptr: Pointer[BufRingPtr[Self.ring_origin], Self.buf_origin]

    # ===------------------------------------------------------------------=== #
    # Life cycle methods
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __init__(
        out self,
        *,
        unsafe_buf_ptr: Pointer[c_void, MutUntrackedOrigin],
        len: UInt32,
        index: UInt16,
        ring_ptr: Pointer[BufRingPtr[Self.ring_origin], Self.buf_origin],
    ):
        self.buf_ptr = unsafe_buf_ptr
        self.len = len
        self.index = index
        self._ring_ptr = ring_ptr

    @always_inline
    def __deinit__(deinit self):
        self._ring_ptr[].unsafe_recycle(index=self.index)

    @always_inline
    def into_index(deinit self) -> UInt16:
        return self.index
