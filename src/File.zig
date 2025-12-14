//! A single file in a txtar archive.

const builtin = @import("builtin");
const File = @This();

/// The name of the file including any directories.
///
/// Note that parser does not sanitize the file name.
/// It may contain "../" or other directory traversal elements.
/// If you're using the file name to access the file system,
/// be sure to sanitize it first.
name: []const u8,

/// The contents of the file.
contents: []const u8,
