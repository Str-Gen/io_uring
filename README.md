# io_uring

This is a Linux [`io_uring`](https://unixism.net/loti/) userspace
interface for Mojo.

This repo includes source code for:

- linux_raw (Linux userspace API)
- mojix (I/O wrappers)
- io_uring

## Ring setup

`IoUring[](sq_entries=128)` opens an ordinary file descriptor and maps the
kernel-allocated rings with the SQ array enabled. `Params()` starts with no
setup flags. This path needs a host that permits io_uring and provides
`IORING_FEAT_SINGLE_MMAP` (Linux 5.4 onward). It uses no preallocated huge
pages. Individual operations and flags have their own kernel requirements.
See [io_uring_setup(2)](https://man7.org/linux/man-pages/man2/io_uring_setup.2.html).

```mojo
from io_uring import IoUring, Params
from mojix.io_uring import IoUringSetupFlags

def main() raises:
    var ring = IoUring[](sq_entries=128)
    var registered_ring = IoUring[is_registered=True](sq_entries=16)

    var params = Params()
    params.flags |= IoUringSetupFlags.NO_SQARRAY
    var ring_without_sq_array = IoUring[](sq_entries=128, params=params)
```

`is_registered=True` selects `NO_MMAP` and `REGISTERED_FD_ONLY` (Linux 6.5
onward). The fork allocates the SQEs and shared SQ/CQ region separately. Each
allocation that exceeds 4 KiB needs an available 2 MiB hugetlb page. The fork
caps each allocation at 2 MiB. Keep setup, use, and teardown on the creating
OS thread, since the registered ring index is local to that thread.
`NO_SQARRAY` is a separate opt-in (Linux 6.6 onward) for either ring type.

Use each ring from one thread at a time. `SINGLE_ISSUER` restricts submission
to one task. `DEFER_TASKRUN` requires `SINGLE_ISSUER` and puts completion waits
on that same task. `SQPOLL` remains disabled in this fork.

## Build and test

This port targets Mojo 1.2.0 on x86-64 Linux. Install Pixi and run:

```sh
pixi run build
pixi run test
```

The build writes three precompiled packages to `build/`. Pass `-I build` to
Mojo when compiling a consumer. The tests submit real kernel operations. In
addition to default setup, the full suite exercises timed waits (`EXT_ARG`,
Linux 5.11), skipped CQEs (5.17), provided buffer rings (5.19), registered
setup (6.5), and explicit `NO_SQARRAY` (6.6). Its registered-ring test uses a
small ring that fits in regular pages. See
[io_uring_enter(2)](https://man7.org/linux/man-pages/man2/io_uring_enter.2.html)
and [io_uring_register_buf_ring(3)](https://man7.org/linux/man-pages/man3/io_uring_register_buf_ring.3.html).

The migration incorporates compatibility work from
[Conobi's Mojo 0.26 port](https://github.com/Conobi/mojo-io-uring/tree/da7e527).

## License

This repository is licensed under the Apache License v2.0 with LLVM Exceptions
(see the LLVM [License](https://llvm.org/LICENSE.txt)).
