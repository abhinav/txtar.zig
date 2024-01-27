//! Archive is a fully parsed txtar file.
//! All files in the file are accessible.

const std = @import("std");

const Archive = @This();
const File = @import("./File.zig");
const Iterator = @import("./Iterator.zig");
const Extractor = @import("./Extractor.zig");

/// FileList is a list of files in the Archive.
///
/// It can be either owned or borrowed.
pub const FileList = union(enum) {
    /// The FileList is owned by the Archive.
    ///
    /// The Archive will free the memory when it is deinitialized.
    owned: std.ArrayList(File),

    /// The FileList was borrowed.
    ///
    /// The Archive will not free the memory when it is deinitialized.
    borrowed: []const File,

    /// Free up any memory allocated by the FileList.
    pub fn deinit(self: FileList) void {
        switch (self) {
            .owned => self.owned.deinit(),
            .borrowed => {},
        }
    }

    /// Returns a read-only slice of the files in the FileList.
    pub fn items(self: FileList) []const File {
        switch (self) {
            .owned => return self.owned.items,
            .borrowed => return self.borrowed,
        }
    }
};

/// Comment section at the top of the txtar file.
comment: []const u8,

/// Files found in the txtar file.
files: FileList,

/// Parses the given txtar file, allocating memory as needed.
/// Use `Iterator.parse` if you want to avoid allocating memory.
///
/// Caller is responsible for calling `deinit` on the returned Archive.
pub fn parse(alloc: std.mem.Allocator, src: []const u8) error{OutOfMemory}!Archive {
    var file_list = std.ArrayList(File).init(alloc);
    errdefer file_list.deinit();

    var it = Iterator.parse(src);
    while (it.next()) |file| {
        try file_list.append(file);
    }

    return .{
        .comment = it.comment,
        .files = .{ .owned = file_list },
    };
}

/// Frees all memory allocated by the Archive.
pub fn deinit(self: Archive) void {
    self.files.deinit();
}

/// Extracts all files in the Archive to the given directory.
/// If the directory does not exist, it will be created.
///
/// Paths in the archive are relative to the destination directory.
/// They are not allowed to escape the destination directory with use of `../`.
pub fn extract(self: Archive, alloc: std.mem.Allocator, dest: []const u8) !void {
    var dir = try std.fs.cwd().makeOpenPath(dest, .{});
    defer dir.close();

    return self.extract_dir(alloc, dir);
}

/// Extracts all files in the Archive to the given directory.
///
/// Paths in the archive are relative to the destination directory.
/// They are not allowed to escape the destination directory with use of `../`.
pub fn extract_dir(self: Archive, alloc: std.mem.Allocator, dir: std.fs.Dir) !void {
    const extractor = try Extractor.init(alloc, dir);
    defer extractor.deinit();

    for (self.files.items()) |file| {
        try extractor.write_file(file);
    }
}

test extract {
    const allocator = std.testing.allocator;

    // Set up a temporary directory.
    var temp_dir = std.testing.tmpDir(.{});
    defer temp_dir.cleanup();
    const temp_dir_path = try temp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(temp_dir_path);

    const archive = Archive{
        .comment = "",
        .files = FileList{ .borrowed = &.{
            .{ .name = "foo/bar.txt", .contents = "hello" },
            .{ .name = "baz/qux.txt", .contents = "world" },
        } },
    };

    try archive.extract(allocator, temp_dir_path);

    var buffer: [128]u8 = undefined;

    // Check that the files were extracted.
    const bar = try temp_dir.dir.readFile("foo/bar.txt", buffer[0..]);
    try std.testing.expectEqualStrings("hello", bar);

    const qux = try temp_dir.dir.readFile("baz/qux.txt", buffer[0..]);
    try std.testing.expectEqualStrings("world", qux);
}

test "file tests" {
    for (File.tests) |tt| {
        errdefer std.debug.print("src:\n----\n{s}\n----\n", .{tt.src});

        var archive = try Archive.parse(std.testing.allocator, tt.src);
        defer archive.deinit();

        try std.testing.expectEqualStrings(tt.comment, archive.comment);

        var idx: usize = 0;
        for (archive.files.items()) |got| {
            try std.testing.expect(idx < tt.files.len);

            const want = tt.files[idx];
            try std.testing.expectEqualStrings(want.name, got.name);
            try std.testing.expectEqualStrings(want.contents, got.contents);

            idx += 1;
        }
    }
}

test "parse allocation error" {
    const allocator = std.testing.failing_allocator;

    const got = Archive.parse(allocator,
        \\-- foo.txt --
        \\hello world
    );

    try std.testing.expectError(error.OutOfMemory, got);
}
