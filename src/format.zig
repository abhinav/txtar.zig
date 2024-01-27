const std = @import("std");

const File = @import("./File.zig");

/// Formatter writes txtar files to a writer of the given type.
/// Use `new_formatter` to construct a Formatter from a writer with a known type.
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
            if (comment) |c| if (c.len > 0) {
                try print_ensure_nl(w, c);
            };

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
        pub fn write_file(self: *Self, f: File) Error!void {
            try self.writer.print("-- {s} --\n", .{f.name});
            try print_ensure_nl(self.writer, f.contents);
        }

        fn print_ensure_nl(w: Writer, s: []const u8) Error!void {
            try w.print("{s}", .{s});
            if (s.len == 0 or s[s.len - 1] != '\n') {
                try w.print("\n", .{});
            }
        }
    };
}

test "file tests" {
    const alloc = std.testing.allocator;

    for (File.tests) |tt| {
        var buf = std.ArrayList(u8).init(alloc);
        defer buf.deinit();

        const w = buf.writer();
        var formatter = try Formatter(@TypeOf(w)).init(w, tt.comment);
        for (tt.files) |f| {
            try formatter.write_file(f);
        }

        const want_src = tt.canonical_src orelse tt.src;
        try std.testing.expectEqualStrings(want_src, buf.items);
    }
}
