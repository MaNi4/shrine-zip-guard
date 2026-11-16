# Changelog

## [1.0.0] - 2026-11-16

Complete rewrite. ZIP checks moved from derivatives to Shrine validation.

### ⚠️ Breaking Changes
- Removed the `create_derivatives` override, the `derivatives` dependency and the automatic `required_files` mode.
- Removed `with_zip`, `EncryptedZipError`, `MissingFileError` and the `fallback` option. Unknown plugin options now raise `ArgumentError`.
- Unexpected errors are no longer rescued.
- I18n keys moved to `shrine.zip_guard.errors.*`; per-uploader message keys were removed.

### Added
- `validate_zip` validation helper with explicit checks: `password:`, `nested_archives:`, `required:`, and per-call `messages:` overrides.
- Recursive password check for nested archives, limited by `max_depth`, `max_entries` and `max_nested_size`.
- ZIP detection by content instead of extension.
- `ZipGuard.extract_one` for size-limited extraction of a single file, with `passthrough:` for uploads that may not be archives.
- Office documents (`.xlsx`, `.docx`, …) are recognised: allowed by `nested_archives: false`, skipped by `required:`.
- CI on Ruby 3.1–3.4.

## [0.3.0] - 2026-08-11

### ⚠️ Breaking Changes
- `rescue ZipGuard::Error` broadened to `rescue StandardError` — now catches corrupt ZIP archives (`Zip::Error`), other unexpected errors, and custom error subclasses like `NestedFileError`. Previously these errors propagated; now they are caught and passed to the fallback handler.
- Fallback callback (`shrine_class.opts[:zip_guard][:fallback]`) is now invoked for all rescued `StandardError` errors, not just `ZipGuard::Error` subclasses.
- `create_derivatives` now explicitly returns `{}` (empty Hash) from all rescue branches. Previously it returned the `errors` array.

### Fixed
- All rescue branches in `create_derivatives` now explicitly return `{}` instead of the error messages array.

### Changed
- Renamed internal method `handle_zip_guard_error` to `handle_error`.
- Renamed internal method `report_fallback` to `report_error`.

## [0.2.0] - 2026-08-06

### Added
- Per-uploader custom I18n messages via `shrine.zip_guard.errors.<uploader_name>`.
- Custom messages are supported for `password_protected`, `missing_file`, and `processing_failed` keys.
- `error_message_key` helper that resolves a custom key based on the uploader class name.

### Changed
- Custom message lookup no longer depends on ActiveSupport `String#underscore`.

## [0.1.0] - 2026-08-06

### Added
- Initial release of `shrine-zip-guard`.
- `Shrine::Plugins::ZipGuard.with_zip` helper for safe ZIP processing.
- Automatic validation via `plugin :zip_guard, required_files: [...]`.
- `EncryptedZipError` for password-protected archives.
- `MissingFileError` for missing required files, with glob pattern support.
- Configurable error fallback handler.
- Default Rails error reporter integration for unexpected errors.
- English I18n translations.
