# Shrine::ZipGuard

A [Shrine](https://shrinerb.com/) plugin that validates uploaded ZIP archives:
it rejects password-protected archives (also when they are nested inside another
archive), can forbid nested archives and can require specific files. It also
ships a size-limited helper for extracting a single file from an archive.

## Installation

```ruby
gem "shrine-zip-guard"
```

## Validation

```ruby
class DocumentUploader < Shrine
  plugin :zip_guard

  Attacher.validate do
    validate_zip password: false, nested_archives: false
  end
end
```

Errors are added during `assign`, so they end up in `record.errors` like any
other Shrine validation.

### Checks

Every check is explicit. Calling `validate_zip` without any of them raises
`ArgumentError`.

| Option | Meaning |
|---|---|
| `password: false` | Rejects the archive if any entry is encrypted, at any nesting level. |
| `password: true` | Requires every file in the archive to be encrypted. |
| `nested_archives: false` | Rejects archives containing other archives. Office documents (`.docx`, `.xlsx`, `.pptx`, `.odt`, …) are allowed. |
| `nested_archives: true` | Allows nested archives (the default when the option is omitted). |
| `required: "*.xml"` | Requires a file matching the pattern in the archive root. Accepts an array; every pattern must match. |

Combine them in a single call:

```ruby
validate_zip password: false, nested_archives: false, required: ["*.xml"]
```

Notes:

- ZIP archives are detected by their content (magic bytes), not by extension. A
  password-protected ZIP renamed to `.pdf` is still rejected.
- Files that are not ZIP archives are ignored. Use `validate_mime_type` and
  `validate_extension` for file types.
- Office documents are ZIP containers too. An uploaded `.xlsx`/`.docx`/… is
  still checked for `password` and `nested_archives`, but `required` does not
  apply to it.
- `required` patterns are matched case-insensitively against the archive root
  (`File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_CASEFOLD`), so
  `"*.{xls,xlsx}"` works. A matching file found only in a subfolder produces a
  dedicated error message.
- `password: true` cannot look inside encrypted entries, so nested archives in
  an encrypted archive are not inspected.
- Encrypted Office documents use a different container format (OLE) and are not
  detected.

### Limits

`password: false` inspects nested archives recursively. To protect against ZIP
bombs, inspection is limited, and an archive exceeding a limit is rejected:

```ruby
plugin :zip_guard,
       max_depth: 3,                         # nesting levels
       max_entries: 10_000,                  # entries across all levels
       max_nested_size: 100 * 1024 * 1024    # bytes extracted from nested archives in total
```

The top-level archive is never extracted; only its central directory and the
first bytes of each entry are read. Nested archives are extracted to temporary
files, and the limit is enforced on the bytes actually written.

## Extracting a single file

```ruby
Shrine::Plugins::ZipGuard.extract_one(file, pattern: "*.xml", max_size: 200 * 1024 * 1024) do |xml, name|
  # xml is a Tempfile with the original extension, deleted after the block
end
```

`file` can be a `Shrine::UploadedFile`, an IO with a path, or a path.

When the upload can be either the archive or the file itself (for example an
XML or a ZIP containing it), pass `passthrough: true`. Files that are not ZIP
archives, and office documents, are then yielded as they are, with their
original filename:

```ruby
Shrine::Plugins::ZipGuard.extract_one(file, pattern: "*.{xls,xlsx}", passthrough: true) do |io, name|
  # io is the extracted file or the original file
end
```

It raises
`Shrine::Plugins::ZipGuard::Error` (with a `key` and a translated `message`)
when the file is not a ZIP archive (without `passthrough`), the archive is
encrypted or invalid, or it does not contain exactly one file
matching the pattern in its root, or when the file exceeds `max_size`.

Unexpected errors (storage failures, bugs) are not rescued.

## Error messages

Messages are translated via I18n. The gem ships English defaults:

```yaml
en:
  shrine:
    zip_guard:
      errors:
        password_forbidden: "ZIP archive is password protected. Please upload an archive without a password."
        password_required: "ZIP archive must be password protected."
        nested_archive: "ZIP archive must not contain other archives."
        missing_file: "ZIP archive does not contain a %{name} file."
        misplaced_file: "The %{name} file must be in the root of the ZIP archive, not in a subfolder."
        multiple_files: "ZIP archive must contain exactly one %{name} file."
        too_deep: "ZIP archive contains too many levels of nested archives."
        too_large: "ZIP archive content is too large."
        too_many_entries: "ZIP archive contains too many files."
        invalid_archive: "File is not a valid ZIP archive."
```

Override any key in your application's locale files to change a message for
the whole application.

To change a message for a single uploader, pass `messages:` to `validate_zip`
(like `message:` in Shrine's `validation_helpers`). Values are strings or
lambdas; lambdas receive `name:` and `pattern:` for required file errors. Keys
you leave out fall back to I18n.

```ruby
validate_zip password: false, required: "*.{xls,xlsx}",
             messages: {
               missing_file: "The archive must contain the explanations spreadsheet.",
               misplaced_file: ->(name:, **) { "Move the #{name} file to the root of the archive." }
             }
```

Messages about required files can use `%{name}` and `%{pattern}`. `%{name}` is
derived from simple patterns (`"*.xml"` → `XML`, `"*.{xls,xlsx}"` → `XLS/XLSX`);
for other patterns it equals the pattern.

## Supported versions

- Ruby >= 3.2
- Shrine >= 3.0, < 4.0
- rubyzip >= 3.0, < 4.0

Shrine 3.9.0 and 3.10.0 raise `NoMethodError` when any validation fails on an
attacher created with `Attacher.new` (without a record) while the `model` and
`remove_invalid` plugins are loaded
([shrine#756](https://github.com/shrinerb/shrine/issues/756)). If you validate
with standalone attachers, use Shrine 3.10.1 or later.

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).
