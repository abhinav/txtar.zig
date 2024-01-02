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
dir: []const u8,

/// Builds a new Extractor that will write to the given directory.
pub fn init(allocator: std.mem.Allocator, dir: []const u8) Extractor {
    return .{ .allocator = allocator, .dir = dir };
}

/// Errors that may occur while extracting.
///
/// PathTraversal indicates that a file attempted to traverse
/// outside the destination directory with a path like "../../foo".
/// This is not supported and is considered a security vulnerability.
pub const WriteError = error{
    PathTraversal,
} || std.mem.Allocator.Error || FSError;

const FSError = std.os.MakeDirError || std.fs.File.OpenError || std.fs.File.WriteError;

/// Writes the given file to the destination directory,
/// creating any missing parent directories,
/// and overwriting any existing file.
///
/// If the file attempts to traverse outside the destination directory,
/// returns error.PathTraversal.
pub fn writeFile(self: *const Extractor, f: File) WriteError!void {
    const path = try std.fs.path.resolve(self.allocator, &.{ self.dir, f.name });
    defer self.allocator.free(path);

    if (!isDescendant(self.dir, path)) return error.PathTraversal;

    const cwd = std.fs.cwd();
    try cwd.makePath(std.fs.path.dirname(path) orelse unreachable);

    const file = try cwd.createFile(path, .{});
    defer file.close();
    try file.writer().writeAll(f.contents);
}

test "writeFile allocation error" {
    const allocator = std.testing.failing_allocator;

    const extractor = Extractor.init(allocator, "foo"); // won't be created
    const got = extractor.writeFile(.{
        .name = "bar/baz/qux",
        .contents = "quux",
    });

    try std.testing.expectError(error.OutOfMemory, got);

    // Verify that the file wasn't created.
    const cwd = std.fs.cwd();
    try std.testing.expectError(error.FileNotFound, cwd.statFile("foo/bar/baz/qux"));
}

test "writeFile traversal error" {
    const allocator = std.testing.allocator;

    // Set up a temporary directory.
    var temp_dir = std.testing.tmpDir(.{});
    defer temp_dir.cleanup();
    const temp_dir_path = try temp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(temp_dir_path);

    const extractor = Extractor.init(allocator, temp_dir_path);

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
