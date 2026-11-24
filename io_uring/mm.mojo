from .cq import Cq
from .params import Entries
from mojix.ctypes import c_void
from mojix.io_uring import (
    Sqe,
    SQE,
    Cqe,
    CQE,
    IoUringParams,
    IoUringSetupFlags,
)
from mojix.errno import Errno
from mojix.fd import FileDescriptor
from mojix.mm import (
    mmap,
    mmap_anonymous,
    munmap,
    madvise,
    ProtFlags,
    MapFlags,
    Advice,
)
from std.sys.info import align_of, size_of
from std.memory import Pointer


struct Region(Movable):
    var ptr: Pointer[c_void, MutUntrackedOrigin]
    var len: UInt

    # ===------------------------------------------------------------------=== #
    # Life cycle methods
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __init__[
        Fd: FileDescriptor
    ](out self, *, fd: Fd, offset: UInt64, len: UInt) raises:
        self.ptr = mmap(
            unsafe_ptr=None,
            len=len,
            prot=ProtFlags.READ | ProtFlags.WRITE,
            flags=MapFlags.SHARED | MapFlags.POPULATE,
            fd=fd,
            offset=offset,
        )
        debug_assert(Int(self.ptr) != 0, "null pointer")
        self.len = len

    @always_inline
    def __init__[
        is_shared: Bool = True
    ](out self, *, len: UInt, flags: MapFlags) raises:
        self.ptr = mmap_anonymous(
            unsafe_ptr=None,
            len=len,
            prot=ProtFlags.READ | ProtFlags.WRITE,
            flags=(MapFlags.SHARED if is_shared else MapFlags.PRIVATE)
            | MapFlags.POPULATE
            | flags,
        )
        debug_assert(Int(self.ptr) != 0, "null pointer")
        self.len = len

    @always_inline
    def __deinit__(deinit self):
        try:
            munmap(unsafe_ptr=self.ptr, len=self.len)
        except:
            pass

    @always_inline
    def __init__(out self, *, deinit move: Self):
        """Moves data of an existing Region into a new one.

        Args:
            move: The existing Region.
        """
        self.ptr = move.ptr
        self.len = move.len

    # ===-------------------------------------------------------------------===#
    # Factory methods
    # ===-------------------------------------------------------------------===#

    @always_inline
    @staticmethod
    def private(out self: Self, *, len: UInt, flags: MapFlags) raises:
        self = Self.__init__[is_shared=False](len=len, flags=flags)

    # ===-------------------------------------------------------------------===#
    # Methods
    # ===-------------------------------------------------------------------===#

    @always_inline
    def dontfork(self) raises:
        madvise(unsafe_ptr=self.ptr, len=self.len, advice=Advice.DONTFORK)

    @always_inline
    def unsafe_ptr[
        T: AnyType
    ](self, *, offset: UInt32, count: UInt32) raises -> Pointer[
        T, MutUntrackedOrigin
    ]:
        comptime assert align_of[T]() > 0
        comptime assert size_of[c_void]() == 1

        if UInt(offset) > self.len or UInt(count) > (
            self.len - UInt(offset)
        ) // UInt(size_of[T]()):
            raise "offset is out of bounds"
        var ptr = self.ptr.unsafe_offset(offset)
        if Int(ptr) & (align_of[T]() - 1):
            raise "region is not properly aligned"
        return ptr.unsafe_bitcast[T]()

    @always_inline
    def unsafe_ptr(self) -> Pointer[c_void, MutUntrackedOrigin]:
        return self.ptr

    @always_inline
    def unsafe_mut_ptr[T: AnyType](mut self) -> Pointer[T, origin_of(self)]:
        """Returns a mutable pointer to the region memory.

        The underlying memory from mmap is always writable; this method
        provides a mutable pointer by rebinding the MutUntrackedOrigin
        pointer to the Region's own mutable origin.
        """
        var p8 = rebind[Pointer[UInt8, origin_of(self)]](
            self.ptr.unsafe_bitcast[UInt8]()
        )
        return p8.unsafe_bitcast[T]()

    @always_inline
    def addr(self) -> UInt64:
        return UInt64(Int(self.ptr))


struct MemoryMapping[sqe: SQE, cqe: CQE](Movable):
    var sqes_mem: Region
    var sq_cq_mem: Region

    # ===------------------------------------------------------------------=== #
    # Life cycle methods
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __init__(out self, *, var sqes_mem: Region, var sq_cq_mem: Region):
        self.sqes_mem = sqes_mem^
        self.sq_cq_mem = sq_cq_mem^

    def __init__(
        out self, sq_entries: UInt32, mut params: IoUringParams
    ) raises:
        var entries = Entries(sq_entries=sq_entries, params=params)
        # FIXME: Get the actual page size value at runtime.
        comptime page_size = 4096
        var sqes_size = entries.sq_entries * UInt32(Self.sqe.size)
        var sq_array_size = (
            0 if params.flags
            & IoUringSetupFlags.NO_SQARRAY else entries.sq_entries
            * UInt32(size_of[UInt32]())
        )
        var sq_cq_size = (
            UInt32(Self.cqe.rings_size)
            + entries.cq_entries * UInt32(Self.cqe.size)
            + sq_array_size
        )

        comptime HUGE_PAGE_SIZE = 1 << 21
        if sqes_size > HUGE_PAGE_SIZE or sq_cq_size > HUGE_PAGE_SIZE:
            raise String(Errno.ENOMEM)

        var flags = MapFlags()
        if sqes_size <= page_size:
            sqes_size = page_size
        else:
            sqes_size = HUGE_PAGE_SIZE
            flags |= MapFlags.HUGETLB | MapFlags.HUGE_2MB

        self.sqes_mem = Region(len=UInt(sqes_size), flags=flags)

        flags = MapFlags()
        if sq_cq_size <= page_size:
            sq_cq_size = page_size
        else:
            sq_cq_size = HUGE_PAGE_SIZE
            flags |= MapFlags.HUGETLB | MapFlags.HUGE_2MB

        self.sq_cq_mem = Region(len=UInt(sq_cq_size), flags=flags)

        params.cq_off.user_addr = self.sq_cq_mem.addr()
        params.sq_off.user_addr = self.sqes_mem.addr()

    @always_inline
    def __init__(out self, *, deinit move: Self):
        """Moves data of an existing MemoryMapping into a new one.

        Args:
            move: The existing MemoryMapping.
        """
        self.sqes_mem = move.sqes_mem^
        self.sq_cq_mem = move.sq_cq_mem^

    # ===-------------------------------------------------------------------===#
    # Methods
    # ===-------------------------------------------------------------------===#

    @always_inline
    def dontfork(self) raises:
        self.sqes_mem.dontfork()
        self.sq_cq_mem.dontfork()
