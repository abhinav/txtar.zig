# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.4.0 - 2024-01-27
### Changed
- Functions and methods are all now `snake_case`.

## 0.3.0 - 2024-01-21
### Added
- `Iterator.extractDir` and `Archive.extractDir` to extract to an open `std.fs.Dir`.

### Changed
- Extractor now operates on `std.fs.Dir` instead of `[]const u8`.
  As a result of this change, `Extractor.init` may return an error,
  and a call to the new `Extractor.deinit` method is required for cleanup.

## 0.2.1 - 2024-01-01
### Fixed
- Fix build.zig.zon for release.

## 0.2.0 - 2024-01-01
### Added
- Add the ability to safely extract a txtar archive into a directory.
  Use `Archive.extract`, `Extractor`, or `Iterator.extract` for this.

### Changed
- `Archive.files` is now a `FileList` tagged union
  differentiating between owned and borrowed lists.

## 0.1.1 - 2023-12-30
### Fixed
- Formatter: Don't add an empty line to the comment section for blank comments.

## 0.1.0 - 2023-12-26

This is the first release of this library.

To use it, ensure that you have Zig 0.11 or newer,
and in a project with a build.zig.zon file,
run the following command:

```bash
zig fetch --save 'https://github.com/abhinav/txtar.zig/archive/0.1.0.tar.gz'
```

See <https://abhinav.github.io/txtar.zig> for documentation.
