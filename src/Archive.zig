//! Archive is a fully parsed txtar file.
//! All files in the file are accessible.

const std = @import("std");

const Archive = @This();
const File = @import("./File.zig");
const Iterator = @import("./Iterator.zig");

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

test "file tests" {
    for (File.tests) |tt| {
        errdefer std.debug.print("src:\n----\n{s}\n----\n", .{tt.src});

        var archive = try Archive.parse(std.testing.allocator, tt.src);
        defer archive.deinit();

        try std.testing.expectEqualStrings(tt.comment, archive.comment);

        var idx: usize = 0;
        for (archive.files) |got| {
            try std.testing.expect(idx < tt.files.len);

            const want = tt.files[idx];
            try std.testing.expectEqualStrings(want.name, got.name);
            try std.testing.expectEqualStrings(want.contents, got.contents);

            idx += 1;
        }
    }
}
