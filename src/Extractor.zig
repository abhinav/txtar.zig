//! Extracts a txtar archive into a directory.
//!
//! Extractor creates directories as needed,
//! and overwrites any existing files.
//! It does not delete files that don't exist in the archive.
//!
//! ## Safety
//!
//! Extractor will refuse to extract files
//! that attempt to traverse outside of the target directory.
//! For example:
//!
//! ```
//! extractor.writeFile(txtar.File{
//!   .name = "../foo.txt",
//!   .contents = "...",
//! });
//! // ERROR: error.PathTraversal
//! ```

const std = @import("std");

const Extractor = @This();
const File = @import("./File.zig");

allocator: std.mem.Allocator,

/// Destination directory.
dir: std.fs.Dir,

/// Absolute path to destination directory.
dir_path: []const u8,

/// Builds a new Extractor that will write to the given directory.
/// The extractor must be released with `deinit`.
pub fn init(allocator: std.mem.Allocator, dir: std.fs.Dir) !Extractor {
    const dir_path = try dir.realpathAlloc(allocator, ".");
    return .{
        .allocator = allocator,
        .dir = dir,
        .dir_path = dir_path,
    };
}

pub fn deinit(self: *const Extractor) void {
    self.allocator.free(self.dir_path);
}

/// Errors that may occur while extracting.
///
/// PathTraversal indicates that a file attempted to traverse
/// outside the destination directory with a path like "../../foo".
/// This is not supported and is considered a security vulnerability.
pub const WriteError = error{
    PathTraversal,
} || std.mem.Allocator.Error || FSError;

const FSError = std.posix.MakeDirError || std.fs.File.OpenError || std.Io.Writer.Error;

/// Writes the given file to the destination directory,
/// creating any missing parent directories,
/// and overwriting any existing file.
///
/// If the file attempts to traverse outside the destination directory,
/// returns error.PathTraversal.
pub fn writeFile(self: *const Extractor, f: File) WriteError!void {
    const resolved_path = try std.fs.path.resolve(self.allocator, &.{ self.dir_path, f.name });
    defer self.allocator.free(resolved_path);
    if (!isDescendant(self.dir_path, resolved_path)) return error.PathTraversal;

    if (std.fs.path.dirname(f.name)) |parent_dir| {
        try self.dir.makePath(parent_dir);
    }

    const file = try self.dir.createFile(f.name, .{});
    defer file.close();

    var buffer: [1024]u8 = undefined;
    var writer = file.writer(&buffer);
    try writer.interface.writeAll(f.contents);
    try writer.interface.flush();
}

test "writeFile allocation error" {
    const allocator = std.testing.failing_allocator;

    var temp_dir = std.testing.tmpDir(.{});
    defer temp_dir.cleanup();

    const got = Extractor.init(allocator, temp_dir.dir);
    try std.testing.expectError(error.OutOfMemory, got);
}

test "writeFile traversal error" {
    const allocator = std.testing.allocator;

    var temp_dir = std.testing.tmpDir(.{});
    defer temp_dir.cleanup();

    const extractor = try Extractor.init(allocator, temp_dir.dir);
    defer extractor.deinit();

    const tests = [_][]const u8{
        "foo/../../bar",
        "foo/../bar/../../baz",
        "../foo",
        "../../../foo",
    };
    for (tests) |name| {
        const got = extractor.writeFile(.{
            .name = name,
            .contents = "quux",
        });
        errdefer std.debug.print("writeFile({s}) should fail\n", .{name});

        try std.testing.expectError(error.PathTraversal, got);
    }
}

// Reports whether child is a descendant of parent.
// Must not be equal to parent.
fn isDescendant(p: []const u8, child: []const u8) bool {
    // Drop trailing slash from parent.
    const parent = if (p.len > 0 and p[p.len - 1] == std.fs.path.sep)
        p[0 .. p.len - 1]
    else
        p;

    if (child.len <= parent.len) return false;

    // "foo/bar" starts with "foo"
    return std.mem.startsWith(u8, child, parent) and
        // and has a "/" after "foo"
        child[parent.len] == std.fs.path.sep;
}

test "isDescendant" {
    const sep = std.fs.path.sep_str;

    const tests = [_]struct {
        parent: []const u8,
        child: []const u8,
        want: bool,
    }{
        .{ .parent = "foo", .child = "foo", .want = false },
        .{ .parent = "foo", .child = "foo" ++ sep ++ "bar", .want = true },
        .{ .parent = "foo" ++ sep, .child = "foo" ++ sep ++ "bar", .want = true },
    };

    for (tests) |tt| {
        const got = isDescendant(tt.parent, tt.child);
        errdefer std.debug.print("isDescendant({s}, {s}) should be {}\n", .{ tt.parent, tt.child, tt.want });
        try std.testing.expectEqual(got, tt.want);
    }
}
