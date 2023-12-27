# txtar.zig 🗃️

txtar.zig is a Zig library for interfacing with the [txtar format](#the-txtar-format).

## API reference

Auto-generated API Reference for the library is available at
<https://abhinav.github.io/txtar.zig/>.

Note that Zig's autodoc is currently in beta.
Some links may be broken in the generated website.

## Installation

Use `zig fetch --save` to pull a version of the library
into your build.zig.zon.
(This requires at least Zig 0.11.)

```bash
zig fetch --save "https://github.com/abhinav/txtar.zig/archive/0.1.0.tar.gz"
```

Then, import the dependency in your build.zig:

```zig
pub fn build(b: *std.Build) void {
    // ...

    const txtar = b.dependency("txtar", .{
        .target = target,
        .optimize = optimize,
    });
```

And add it to the executables that need it:

```zig
    const exe = b.addExecutable(.{
        // ...
    });
    exe.addModule("txtar", txtar.module("txtar"));
```

Finally, in your code:

```zig
const txtar = @import("txtar");
```

These instructions may grow out of date as the Zig package management tooling
and APIs evolve.

## The txtar format

txtar is a simple text-based format to store multiple files together.
It looks like this:

```
-- foo.txt --
Everything here is part of foo.txt
until the next file header.
-- bar/baz.txt --
Similarly, everything here
is part of bar/baz.txt
until the next header or end of file.
```

It's meant to be human-readable and easily diff-able,
making it a good candidate for test case data.

See [golang.org/x/tools/txtar](https://pkg.go.dev/golang.org/x/tools/txtar),
which defines the format and provides its Go implementation.

## License

This software is made available under the BSD3 license.
