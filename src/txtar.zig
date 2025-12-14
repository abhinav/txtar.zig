//! txtar is a simple file format for storing multiple text files together.
//!
//! # The txtar format
//!
//! A txtar file is a single text file with a simple structure:
//! Each file is preceded by a line starting with `-- NAME --`
//! where `NAME` is a relative file name.
//! The file contents follow on the next line
//! and continue until the next such header or end of file.
//!
//! ```
//! -- foo.txt --
//! Setting up the foo.
//! -- bar/baz.txt --
//! Cleaning up the bar.
//! ```
//!
//! Anything that precedes the first header is treated as a comment.
//!
//! ```
//! This is a freeform comment area.
//! It may describe the contents that follow,
//! or define additional information about the archive.
//! -- foo.txt --
//! Setting up the foo.
//! -- bar/baz.txt --
//! Cleaning up the bar.
//! ```
//!
//! A few important points about the format:
//!
//! - There are no possible syntax errors.
//! - There are minimal restrictions on the file names.
//!   They may contain "../" or other directory traversal elements.
//!   Code that interfaces with the file system should sanitize the file names.
//! - It's not possible to represent files that do not end in a newline,
//!   except for the last file in the archive.
//!   Code should assume that all files end in a newline.
//!
//! [golang.org/x/tools/txtar](https://pkg.go.dev/golang.org/x/tools/txtar)
//! defines the format and provides a Go implementation.
//!
//! # Using this package
//!
//! ## Parsing txtar files
//!
//! Use `Iterator.parse` to iterate over the contents of a txtar file
//! without dynamically allocating memory.
//!
//! ```
//! var it = txtar.Iterator.parse(src);
//! while (it.next()) |file| {
//!    // ...
//! }
//! ```
//!
//! Or use `Archive.parse` to parse the entire txtar file at once
//! if you don't mind allocating memory.
//!
//! ```
//! const archive = try txtar.Archive.parse(allocator, src);
//! defer archive.deinit();
//!
//! for (archive.files.items()) |file| {
//!    // ...
//! }
//! ```
//!
//! ## Writing txtar files
//!
//! Use `newFormatter` to write txtar files to a writer.
//!
//! ```
//! var file: std.fs.File = // ...
//! var f = try txtar.newFormatter(file.writer(), "This is a comment.");
//! try f.writeFile(.{
//!    .name = "foo/bar.txt",
//!    .contents = "Hello, world!\n",
//! });
//! ```
//!
//! ## Extracting txtar files
//!
//! This package supports a few different ways of *safely*
//! extracting txtar files into directories:
//! `Archive.extract` and `Iterator.extract` provide a higher-level API,
//! while `Extractor` provides a more direct interface.
//!
//! The usage for `Archive.extract` and `Iterator.extract` is similar:
//!
//! ```
//! const archive = // ...
//! archive.extract(allocator, "path/to/dir");
//!
//! var iter = // ...
//! iter.extract(allocator, "path/to/dir");
//! ```
//!
//! Whereas with `Extractor`, you must manually iterate over the files:
//!
//! ```
//! const extractor = try txtar.Extractor.init(allocator, dir);
//! defer extractor.deinit();
//!
//! try extractor.writeFile(txtar.File{ ... });
//! try extractor.writeFile(txtar.File{ ... });
//! ```

const std = @import("std");

pub const Iterator = @import("./Iterator.zig");
pub const Formatter = @import("./format.zig").Formatter;
pub const File = @import("./File.zig");
pub const Archive = @import("./Archive.zig");
pub const Extractor = @import("./Extractor.zig");

/// Constructs a Formatter from a writer with a known type.
///
/// This can be more convenient than instantiating the Formatter type directly.
pub fn newFormatter(writer: anytype, comment: ?[]const u8) !Formatter(@TypeOf(writer)) {
    return try Formatter(@TypeOf(writer)).init(writer, comment);
}

test newFormatter {
    var buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer buf.deinit();

    var f = try newFormatter(buf.writer(), "comment");
    try f.writeFile(.{ .name = "foo.txt", .contents = "foo" });
    try f.writeFile(.{ .name = "bar.txt", .contents = "bar\n" });

    try std.testing.expectEqualStrings(
        \\comment
        \\-- foo.txt --
        \\foo
        \\-- bar.txt --
        \\bar
        \\
    ,
        buf.items,
    );
}

test Iterator {
    const src =
        \\Optional comment section
        \\before the first file.
        \\-- foo.txt --
        \\Setting up the foo.
        \\-- bar/baz.txt --
        \\Cleaning up the bar.
    ;

    var it = Iterator.parse(src);
    try std.testing.expectEqualStrings(
        "Optional comment section\n" ++
            "before the first file.\n",
        it.comment,
    );

    const foo = it.next() orelse @panic("expected foo.txt");
    try std.testing.expectEqualStrings("foo.txt", foo.name);
    try std.testing.expectEqualStrings("Setting up the foo.\n", foo.contents);

    const baz = it.next() orelse @panic("expected baz.txt");
    try std.testing.expectEqualStrings("bar/baz.txt", baz.name);
    try std.testing.expectEqualStrings("Cleaning up the bar.", baz.contents);

    try std.testing.expect(it.next() == null);
}

test Archive {
    const allocator = std.testing.allocator;

    const src =
        \\Optional comment section
        \\before the first file.
        \\-- foo.txt --
        \\Setting up the foo.
        \\-- bar/baz.txt --
        \\Cleaning up the bar.
    ;

    // Parse the archive.
    const archive = try Archive.parse(allocator, src);
    defer archive.deinit();

    // The archive comment is accessible.
    try std.testing.expectEqualStrings(
        "Optional comment section\n" ++
            "before the first file.\n",
        archive.comment,
    );

    // Set up a temporary directory.
    var temp_dir = std.testing.tmpDir(.{});
    defer temp_dir.cleanup();
    const temp_dir_path = try temp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(temp_dir_path);

    // Extract the files into the temporary directory.
    try archive.extract(allocator, temp_dir_path);

    var buffer: [128]u8 = undefined;

    // Read the files and verify their contents.
    const foo = try temp_dir.dir.readFile("foo.txt", &buffer);
    try std.testing.expectEqualStrings("Setting up the foo.\n", foo);

    const baz = try temp_dir.dir.readFile("bar/baz.txt", &buffer);
    try std.testing.expectEqualStrings("Cleaning up the bar.", baz);
}

test {
    std.testing.refAllDecls(@This());
}
