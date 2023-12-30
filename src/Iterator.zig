//! Iterates over the contents of a single txtar file
//! comprised of multiple text files.

const std = @import("std");

const Iterator = @This();
const File = @import("./File.zig");

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

test "file tests" {
    for (File.tests) |tt| {
        errdefer std.debug.print("src:\n----\n{s}\n----\n", .{tt.src});

        var iter = Iterator.parse(tt.src);
        try std.testing.expectEqualStrings(tt.comment, iter.comment);

        var idx: usize = 0;
        while (iter.next()) |got| {
            try std.testing.expect(idx < tt.files.len);

            const want = tt.files[idx];
            try std.testing.expectEqualStrings(want.name, got.name);
            try std.testing.expectEqualStrings(want.contents, got.contents);

            idx += 1;
        }
    }
}
