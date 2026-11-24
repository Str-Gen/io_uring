# io_uring

This is a Linux [`io_uring`](https://unixism.net/loti/) userspace
interface for Mojo.

This repo includes source code for:

- linux_raw (Linux userspace API)
- mojix (I/O wrappers)
- io_uring


## Build and test

This port targets Mojo 1.2.0 on x86-64 Linux. Install Pixi and run:

```sh
pixi run build
pixi run test
```

The build writes three precompiled packages to `build/`. Pass `-I build` to
Mojo when compiling a consumer. The tests submit real kernel operations and
require a host that permits io_uring. The library uses Mojo standard library
APIs and Linux syscalls directly.

The migration incorporates compatibility work from
[Conobi's Mojo 0.26 port](https://github.com/Conobi/mojo-io-uring/tree/da7e527).

## License

This repository is licensed under the Apache License v2.0 with LLVM Exceptions
(see the LLVM [License](https://llvm.org/LICENSE.txt)).
