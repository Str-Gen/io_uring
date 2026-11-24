from mojix import sigset_t
from mojix.ctypes import c_void
from mojix.io_uring import EnterArg, IoUringEnterFlags, IoUringGetEventsArg
from mojix.timespec import Timespec
from std.sys.info import size_of
from std.memory import Pointer


struct WaitArg[
    sigmask_origin: ImmOrigin,
    timespec_origin: ImmOrigin,
]:
    comptime enter_flags = IoUringEnterFlags.EXT_ARG

    var arg: IoUringGetEventsArg

    # ===------------------------------------------------------------------=== #
    # Life cycle methods
    # ===------------------------------------------------------------------=== #

    @always_inline
    def __init__(out self):
        self.arg = IoUringGetEventsArg()

    @always_inline
    def __init__[
        origin: ImmOrigin
    ](
        out self: WaitArg[origin, ImmStaticOrigin],
        ref[origin] sigmask: sigset_t,
    ):
        self.arg = IoUringGetEventsArg()
        self.arg.sigmask = UInt64(Int(Pointer(to=sigmask)))
        self.arg.sigmask_sz = UInt32(size_of[sigset_t]())

    @always_inline
    def __init__[
        origin: ImmOrigin
    ](
        out self: WaitArg[ImmStaticOrigin, origin],
        ref[origin] timespec: Timespec,
    ):
        self.arg = IoUringGetEventsArg()
        self.arg.ts = UInt64(Int(Pointer(to=timespec)))

    @always_inline
    def __init__(
        out self,
        ref[Self.sigmask_origin] sigmask: sigset_t,
        ref[Self.timespec_origin] timespec: Timespec,
    ):
        self.arg = IoUringGetEventsArg()
        self.arg.sigmask = UInt64(Int(Pointer(to=sigmask)))
        self.arg.sigmask_sz = UInt32(size_of[sigset_t]())
        self.arg.ts = UInt64(Int(Pointer(to=timespec)))

    # ===-------------------------------------------------------------------===#
    # Methods
    # ===-------------------------------------------------------------------===#

    @always_inline
    def as_enter_arg(
        self,
    ) -> EnterArg[
        UInt(size_of[IoUringGetEventsArg]()),
        Self.enter_flags,
        origin_of(self),
    ]:
        return EnterArg[
            UInt(size_of[IoUringGetEventsArg]()),
            Self.enter_flags,
            origin_of(self),
        ](arg_unsafe_ptr=UInt(Int(Pointer(to=self.arg))))
