# txtar.zig 🗃️

txtar.zig is a Zig library for interfacing with the [txtar format](#txtar-format).

## API reference

Auto-generated API Reference for the library is available at
<https://abhinav.github.io/txtar.zig/>.

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
