# Shrine::ZipGuard

A [Shrine](https://shrinerb.com/) plugin for safe ZIP derivative processing.

It catches common ZIP errors during derivative creation — password-protected
archives and missing required files — and converts them into friendly, I18n-ready
error messages attached to `attacher.errors`.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "shrine-zip-guard"
```

And then execute:

```bash
bundle install
```

## Usage

### Automatic validation

If you only need to validate that the uploaded ZIP contains certain files, enable
the plugin with `required_files`:

```ruby
class XmlUploader < Shrine
  plugin :derivatives
  plugin :zip_guard, required_files: ["*.xml"]
end
```

This checks that the ZIP is not password-protected and that it contains at least
one file matching each glob pattern. Patterns are matched against the root of the
archive only. If you want to allow nested files, use a recursive pattern:

```ruby
plugin :zip_guard, required_files: ["**/*.xml"]
```

For a specific subdirectory, include the path in the pattern:

```ruby
plugin :zip_guard, required_files: ["data/*.xml"]
```

### Custom processing with `with_zip`

If you need to run your own logic (for example extracting files or checking
specific paths), use the `with_zip` helper inside your `Attacher.derivatives` block:

```ruby
class XmlUploader < Shrine
  plugin :derivatives
  plugin :zip_guard

  Attacher.derivatives do |original|
    Shrine::Plugins::ZipGuard.with_zip(original, required_files: ["*.xml"]) do |zip_file|
      xmls = zip_file.glob("*.xml")

      if xmls.size == 1
        extracted = Tempfile.new(["extracted", ".xml"], binmode: true)
        extracted.write(xmls.first.get_input_stream.read)
        extracted.rewind
        { extracted_xml: extracted }
      else
        {}
      end
    end
  end
end
```

Note that `with_zip` performs its own `required_files` check, so you should not also
pass `required_files` to the plugin when you provide a custom `derivatives` block.

## Error messages

All user-facing errors are translated via I18n. The gem ships with English
defaults under the `shrine.zip_guard` key:

```yaml
en:
  shrine:
    zip_guard:
      password_protected: "ZIP file is password protected. Please upload an unprotected file."
      missing_file: "Archive does not contain required file matching '%{pattern}'."
      processing_failed: "File could not be processed. Please try again or contact support."
```

### Per-uploader custom messages

You can override any message for a specific uploader by adding a key under
`shrine.zip_guard.errors.<uploader_name>`:

```yaml
en:
  shrine:
    zip_guard:
      missing_file: "Archive does not contain required file matching '%{pattern}'."
      errors:
        digital_box_rd_uploader:
          missing_file: "XML file must be at the root level of the ZIP archive."
          password_protected: "This ZIP is password protected."
          processing_failed: "Could not process this XML ZIP."
```

If the per-uploader key exists, it is used; otherwise the default key is used.
The class name is converted with `underscore`, so `MyUploaders::XmlUploader`
would become `my_uploaders/xml_uploader`.

## Custom fallback for unexpected errors

By default, unexpected `ZipGuard::Error` subclasses are reported to the Rails error
reporter (if available) and a generic `processing_failed` message is added to
`attacher.errors`. You can override this with your own handler:

```ruby
plugin :zip_guard,
       required_files: ["*.xml"],
       fallback: lambda { |error, attacher|
         Sentry.capture_exception(error)
         attacher.errors << "Custom processing error: #{error.message}"
       }
```

## Supported versions

- Ruby >= 3.1
- Shrine >= 3.0, < 4.0

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).
