# Changelog

## [Unreleased]

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
