//! A single file in a txtar archive.

const builtin = @import("builtin");
const File = @This();

/// The name of the file including any directories.
///
/// Note that iterator does not sanitize the file name.
/// It may contain "../" or other directory traversal elements.
/// If you're using the file name to access the file system,
/// be sure to sanitize it first.
name: []const u8,

/// The contents of the file.
contents: []const u8,

/// Export these only for testing.
pub usingnamespace if (!builtin.is_test) struct {} else struct {
    pub const tests = [_]struct {
        src: []const u8,
        comment: []const u8 = "",
        files: []const File = &.{},

        // Canonicalized form of src if different from src.
        canonical_src: ?[]const u8 = null,
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
            .comment =
            \\This is a comment.
            \\It can span multiple lines.
            ,
            .canonical_src =
            \\This is a comment.
            \\It can span multiple lines.
            \\
        },
        .{
            // Trailing newline in file.
            .src =
            \\-- foo.txt --
            \\foo
            \\
            ,
            .files = &.{
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
            .files = &.{
                .{
                    .name = "foo.txt",
                    .contents = "foo",
                },
            },
            .canonical_src =
            \\-- foo.txt --
            \\foo
            \\
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
            .files = &.{
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
            \\
            ,
            .files = &.{
                .{
                    .name = "foo.txt",
                    .contents = "foo\n-- --\nbar\n--  --\nbaz\n--   --\nqux\n",
                },
            },
        },
    };
};
