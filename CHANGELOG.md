# Changelog

## [Unreleased]

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
