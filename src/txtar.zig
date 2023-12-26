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
//! for (archive.files) |file| {
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

const std = @import("std");

/// A single file in the archive.
pub const File = struct {
    /// The name of the file including any directories.
    ///
    /// Note that iterator does not sanitize the file name.
    /// It may contain "../" or other directory traversal elements.
    /// If you're using the file name to access the file system,
    /// be sure to sanitize it first.
    name: []const u8,

    /// The contents of the file.
    contents: []const u8,
};

/// Iterates over the contents of a single txtar file
/// comprised of multiple text files.
pub const Iterator = struct {
    /// Comment section at the top of the txtar file.
    /// This includes the newline that the comment section ends with.
    comment: []const u8,

    /// The raw contents of the txtar file.
    raw: []const u8,

    /// Information about the next file in the archive, if any.
    /// This should be considered an internal implementation detail.
    next_hdr: ?FileHeader,

    /// Parses a txtar file, returning an iterator over its contents.
    /// If allocating new memory is acceptable,
    /// consider using `Archive.parse` for a simpler API.
    ///
    /// The iterator does not copy the file contents.
    /// The source must remain valid for the lifetime of the iterator.
    pub fn parse(src: []const u8) Iterator {
        const hdr = FileHeader.next(src, 0) orelse {
            // If there are no files, the entire src is a comment.
            return .{
                .comment = src,
                .raw = src,
                .next_hdr = null,
            };
        };

        return .{
            .comment = src[0..hdr.offset],
            .raw = src,
            .next_hdr = hdr,
        };
    }

    /// Returns the next file in the archive,
    /// or null if there are no more files.
    /// The returned File is valid as long as the Iterator exists.
    pub fn next(self: *Iterator) ?File {
        const hdr = self.next_hdr orelse return null;
        const name = hdr.name;
        const body_start = hdr.body_offset;

        // Find the next file header.
        self.next_hdr = FileHeader.next(self.raw, body_start);
        const body_end = if (self.next_hdr) |next_hdr|
            next_hdr.offset
        else
            self.raw.len;

        return .{
            .name = name,
            .contents = self.raw[body_start..body_end],
        };
    }
};

/// Archive is a fully parsed txtar file.
/// All files in the file are accessible.
pub const Archive = struct {
    /// Allocator used to create the Archive.
    allocator: std.mem.Allocator,

    /// Comment section at the top of the txtar file.
    comment: []const u8,

    /// Files found in the txtar file.
    files: []const File,

    /// Parses the given txtar file, allocating memory as needed.
    /// Use `Iterator.parse` if you want to avoid allocating memory.
    ///
    /// Caller is responsible for calling `deinit` on the returned Archive.
    pub fn parse(alloc: std.mem.Allocator, src: []const u8) error{OutOfMemory}!Archive {
        var file_list = std.ArrayList(File).init(alloc);
        defer file_list.deinit();

        var it = Iterator.parse(src);
        while (it.next()) |file| {
            try file_list.append(file);
        }

        return .{
            .comment = it.comment,
            .files = try file_list.toOwnedSlice(),
            .allocator = alloc,
        };
    }

    /// Frees all memory allocated by the Archive.
    pub fn deinit(self: Archive) void {
        self.allocator.free(self.files);
    }
};

/// Formatter writes txtar files to a writer of the given type.
/// Use `newFormatter` to construct a Formatter from a writer with a known type.
pub fn Formatter(comptime Writer: type) type {
    return struct {
        /// Error type returned by the Formatter.
        pub const Error = Writer.Error;

        const Self = @This();

        /// Writer used to write the txtar file.
        writer: Writer,

        /// Builds a formatter to write to the given writer.
        ///
        /// Comment, if non-null, is written at the top of the file.
        pub fn init(w: Writer, comment: ?[]const u8) Error!Self {
            if (comment) |c| {
                try printEnsureNL(w, c);
            }

            return .{ .writer = w };
        }

        /// Writes a single file to the txtar archive.
        ///
        /// If the file does not include a trailing newline,
        /// one will be added.
        ///
        /// Note that the formatter does not sanitize the file name.
        /// If it contains directory traversal elements like "../",
        /// they'll be written to the txtar file as-is.
        pub fn writeFile(self: *Self, file: File) Error!void {
            try self.writer.print("-- {s} --\n", .{file.name});
            try printEnsureNL(self.writer, file.contents);
        }

        fn printEnsureNL(w: Writer, s: []const u8) Error!void {
            try w.print("{s}", .{s});
            if (s.len == 0 or s[s.len - 1] != '\n') {
                try w.print("\n", .{});
            }
        }
    };
}

/// Constructs a Formatter from a writer with a known type.
///
/// This can be more convenient than instantiating the Formatter type directly.
pub fn newFormatter(writer: anytype, comment: ?[]const u8) !Formatter(@TypeOf(writer)) {
    return try Formatter(@TypeOf(writer)).init(writer, comment);
}

test newFormatter {
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();

    var f = try newFormatter(buf.writer(), "comment");
    try f.writeFile(.{
        .name = "foo.txt",
        .contents = "foo",
    });
    try f.writeFile(.{
        .name = "bar.txt",
        .contents = "bar\n",
    });

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

// Information about a single file in the archive.
// This is used by the Iterator to find the next file.
const FileHeader = struct {
    // Name of the file.
    name: []const u8,

    // Position where the header for the file begins.
    offset: usize,

    // Position where the body for the file begins.
    // This is the offset right after the " --\n".
    body_offset: usize,

    // Scans to next file in the given source
    // starting at the given position.
    fn next(src: []const u8, start_pos: usize) ?FileHeader {
        var offset = start_pos;
        while (true) {
            // Scan until the next "-- ".
            if (!std.mem.startsWith(u8, src[offset..], "-- ")) {
                offset = std.mem.indexOfPos(u8, src, offset, "\n-- ") orelse return null;
            }

            const line_end_idx = std.mem.indexOfPos(u8, src, offset, "\n") orelse src.len;
            const line = src[offset..line_end_idx];
            if (line.len < 7) {
                // Can't contain "-- x --".
                offset = line_end_idx + 1;
                continue;
            }

            if (!std.mem.endsWith(u8, line, " --")) {
                // Open "-- " but not close " --".
                offset = line_end_idx + 1;
                continue;
            }

            const name = std.mem.trim(u8, line[3 .. line.len - 3], " ");
            if (name.len == 0) {
                // Open and close markers,  but no name.
                offset = line_end_idx + 1;
                continue;
            }

            // "-- NAME --".
            const body_offset = @min(line_end_idx + 1, src.len);
            return .{
                .name = name,
                .offset = offset,
                .body_offset = body_offset,
            };
        }
    }
};

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
    const src =
        \\Optional comment section
        \\before the first file.
        \\-- foo.txt --
        \\Setting up the foo.
        \\-- bar/baz.txt --
        \\Cleaning up the bar.
    ;

    const archive = try Archive.parse(std.testing.allocator, src);
    defer archive.deinit();

    try std.testing.expectEqualStrings(
        "Optional comment section\n" ++
            "before the first file.\n",
        archive.comment,
    );

    try std.testing.expectEqual(archive.files.len, 2);

    const foo = archive.files[0];
    try std.testing.expectEqualStrings("foo.txt", foo.name);
    try std.testing.expectEqualStrings("Setting up the foo.\n", foo.contents);

    const baz = archive.files[1];
    try std.testing.expectEqualStrings("bar/baz.txt", baz.name);
    try std.testing.expectEqualStrings("Cleaning up the bar.", baz.contents);
}

test "iterator cases" {
    const tests = [_]struct {
        src: []const u8,
        wantComment: []const u8 = "",
        wantFiles: []const File = &.{},
    }{
        .{
            // Empty file.
            .src = "",
        },
        .{
            // Just a comment.
            .src =
            \\This is a comment.
            \\It can span multiple lines.
            ,
            .wantComment =
            \\This is a comment.
            \\It can span multiple lines.
        },
        .{
            // Trailing newline in file.
            .src =
            \\-- foo.txt --
            \\foo
            \\
            ,
            .wantFiles = &.{
                .{
                    .name = "foo.txt",
                    .contents = "foo\n",
                },
            },
        },
        .{
            // Extra whitespace around file name.
            .src =
            \\--     foo.txt    --
            \\foo
            ,
            .wantFiles = &.{
                .{
                    .name = "foo.txt",
                    .contents = "foo",
                },
            },
        },
        .{
            // "-- NAME" but not "-- NAME --".
            .src =
            \\-- foo.txt --
            \\foo
            \\-- bar.txt
            \\bar
            \\-- bar.txt --
            \\bar
            \\--
            \\-- ;
            \\
            ,
            .wantFiles = &.{
                .{
                    .name = "foo.txt",
                    .contents = "foo\n-- bar.txt\nbar\n",
                },
                .{
                    .name = "bar.txt",
                    .contents = "bar\n--\n-- ;\n",
                },
            },
        },
        .{
            // "-- --" variants
            .src =
            \\-- foo.txt --
            \\foo
            \\-- --
            \\bar
            \\--  --
            \\baz
            \\--   --
            \\qux
            ,
            .wantFiles = &.{
                .{
                    .name = "foo.txt",
                    .contents = "foo\n-- --\nbar\n--  --\nbaz\n--   --\nqux",
                },
            },
        },
    };

    for (tests) |tt| {
        errdefer std.debug.print("src:\n----\n{s}\n----\n", .{tt.src});

        const archive = try Archive.parse(std.testing.allocator, tt.src);
        defer archive.deinit();

        try std.testing.expectEqualStrings(tt.wantComment, archive.comment);

        var idx: usize = 0;
        for (archive.files) |got| {
            try std.testing.expect(idx < tt.wantFiles.len);

            const want = tt.wantFiles[idx];
            try std.testing.expectEqualStrings(want.name, got.name);
            try std.testing.expectEqualStrings(want.contents, got.contents);

            idx += 1;
        }
    }
}
