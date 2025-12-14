const File = @import("./File.zig");

pub const parse_tests = [_]struct {
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
