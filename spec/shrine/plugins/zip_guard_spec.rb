# frozen_string_literal: true

require "stringio"

RSpec.describe Shrine::Plugins::ZipGuard do
  def uploader(**plugin_options, &validation)
    Class.new(Shrine) do
      plugin :zip_guard, **plugin_options
      self::Attacher.validate(&validation)
    end
  end

  def validate(path, uploader_class)
    attacher = uploader_class::Attacher.new
    File.open(path, "rb") { |file| attacher.assign(file) }
    attacher.errors
  end

  def message(key, **options)
    described_class::Error.new(key, **options).message
  end

  let(:plain_zip) { build_zip("data.xml" => "<a/>") }
  let(:encrypted_zip) { build_zip({ "data.xml" => "<a/>" }, password: "secret") }

  describe "plugin options" do
    it "rejects unknown options" do
      expect { uploader(fallback: -> {}) { nil } }.to raise_error(ArgumentError, /fallback/)
    end
  end

  describe "#validate_zip arguments" do
    it "requires at least one check" do
      expect { validate(plain_zip, uploader { validate_zip }) }.to raise_error(ArgumentError, /requires/)
    end

    it "rejects unknown checks" do
      expect { validate(plain_zip, uploader { validate_zip(foo: true) }) }.to raise_error(ArgumentError, /foo/)
    end

    it "rejects non-boolean password" do
      expect { validate(plain_zip, uploader { validate_zip(password: nil) }) }.to raise_error(ArgumentError, /password/)
    end
  end

  describe "password: false" do
    let(:uploader_class) { uploader { validate_zip password: false } }

    it "accepts a plain archive" do
      expect(validate(plain_zip, uploader_class)).to be_empty
    end

    it "rejects an encrypted archive" do
      expect(validate(encrypted_zip, uploader_class)).to eq([message(:password_forbidden)])
    end

    it "rejects an archive with a single encrypted entry among plain ones" do
      path = build_partially_encrypted_zip(plain: { "a.txt" => "a" }, encrypted: { "b.txt" => "b" })

      expect(validate(path, uploader_class)).to eq([message(:password_forbidden)])
    end

    it "accepts an empty archive" do
      expect(validate(build_zip, uploader_class)).to be_empty
    end

    it "rejects an encrypted archive with a misleading extension" do
      path = write_file(File.binread(encrypted_zip), name: "report.pdf")

      expect(validate(path, uploader_class)).to eq([message(:password_forbidden)])
    end

    it "rejects an encrypted archive nested inside a plain one" do
      path = build_zip("inner.zip" => File.binread(encrypted_zip))

      expect(validate(path, uploader_class)).to eq([message(:password_forbidden)])
    end

    it "rejects an encrypted archive renamed as a document inside a plain one" do
      path = build_zip("table.xlsx" => File.binread(encrypted_zip))

      expect(validate(path, uploader_class)).to eq([message(:password_forbidden)])
    end

    it "accepts plain nested archives within max_depth" do
      path = build_zip("outer.zip" => nested_zip(2, zip_content("a.txt" => "a")))

      expect(validate(path, uploader_class)).to be_empty
    end

    it "rejects nesting deeper than max_depth" do
      path = build_zip("outer.zip" => nested_zip(1, zip_content("a.txt" => "a")))

      expect(validate(path, uploader(max_depth: 1) { validate_zip password: false })).to eq([message(:too_deep)])
    end

    it "rejects nested archives over the extraction budget" do
      path = build_zip("inner.zip" => zip_content("random.bin" => SecureRandom.bytes(5_000)))

      result = validate(path, uploader(max_nested_size: 1_000) { validate_zip password: false })
      expect(result).to eq([message(:too_large)])
    end

    it "rejects archives with too many entries" do
      path = build_zip((1..5).to_h { |i| ["#{i}.txt", "x"] })

      result = validate(path, uploader(max_entries: 3) { validate_zip password: false })
      expect(result).to eq([message(:too_many_entries)])
    end

    it "rejects a corrupted archive" do
      path = write_file("PK\x03\x04#{"garbage" * 10}", name: "broken.zip")

      expect(validate(path, uploader_class)).to eq([message(:invalid_archive)])
    end

    it "ignores files that are not ZIP archives" do
      path = write_file("%PDF-1.7", name: "doc.pdf")

      expect(validate(path, uploader_class)).to be_empty
    end

    it "works with remote storage" do
      uploader_class = uploader { validate_zip password: false }
      uploader_class.storages = { cache: Shrine::Storage::Memory.new, store: Shrine::Storage::Memory.new }

      expect(validate(encrypted_zip, uploader_class)).to eq([message(:password_forbidden)])
    end
  end

  describe "password: true" do
    let(:uploader_class) { uploader { validate_zip password: true } }

    it "accepts an encrypted archive" do
      expect(validate(encrypted_zip, uploader_class)).to be_empty
    end

    it "rejects a plain archive" do
      expect(validate(plain_zip, uploader_class)).to eq([message(:password_required)])
    end

    it "rejects a partially encrypted archive" do
      path = build_partially_encrypted_zip(plain: { "a.txt" => "a" }, encrypted: { "b.txt" => "b" })

      expect(validate(path, uploader_class)).to eq([message(:password_required)])
    end

    it "rejects an empty archive" do
      expect(validate(build_zip, uploader_class)).to eq([message(:password_required)])
    end

    it "checks required files by name in an encrypted archive" do
      uploader_class = uploader { validate_zip password: true, required: ["*.xml", "*.pdf"] }

      expect(validate(encrypted_zip, uploader_class)).to eq([message(:missing_file, pattern: "*.pdf")])
    end

    it "does not inspect encrypted entries for nested archives" do
      path = build_zip({ "inner.zip" => zip_content("a.txt" => "a") }, password: "secret")

      expect(validate(path, uploader { validate_zip password: true, nested_archives: false })).to be_empty
    end
  end

  describe "nested_archives: false" do
    let(:uploader_class) { uploader { validate_zip password: false, nested_archives: false } }

    it "rejects a nested archive" do
      path = build_zip("inner.zip" => zip_content("a.txt" => "a"))

      expect(validate(path, uploader_class)).to eq([message(:nested_archive)])
    end

    it "rejects a nested archive with a misleading extension" do
      path = build_zip("inner.pdf" => zip_content("a.txt" => "a"))

      expect(validate(path, uploader_class)).to eq([message(:nested_archive)])
    end

    it "accepts office documents" do
      path = build_zip("table.xlsx" => zip_content("[Content_Types].xml" => "<Types/>"))

      expect(validate(path, uploader_class)).to be_empty
    end

    it "rejects an empty nested archive" do
      path = build_zip("inner.zip" => File.binread(build_zip))

      expect(validate(path, uploader_class)).to eq([message(:nested_archive)])
    end

    it "accepts nested archives with nested_archives: true" do
      path = build_zip("inner.zip" => zip_content("a.txt" => "a"))

      expect(validate(path, uploader { validate_zip nested_archives: true })).to be_empty
    end

    it "works without the password check" do
      path = build_zip("inner.zip" => zip_content("a.txt" => "a"))

      expect(validate(path, uploader { validate_zip nested_archives: false })).to eq([message(:nested_archive)])
    end
  end

  describe "required:" do
    it "accepts an archive with the required file in its root" do
      expect(validate(plain_zip, uploader { validate_zip required: "*.xml" })).to be_empty
    end

    it "matches case-insensitively" do
      path = build_zip("DATA.XML" => "<a/>")

      expect(validate(path, uploader { validate_zip required: "*.xml" })).to be_empty
    end

    it "requires every pattern from an array" do
      result = validate(plain_zip, uploader { validate_zip required: ["*.xml", "*.pdf"] })

      expect(result).to eq([message(:missing_file, pattern: "*.pdf")])
    end

    it "reports a file placed in a subfolder" do
      path = build_zip("dir/data.xml" => "<a/>")

      result = validate(path, uploader { validate_zip required: "*.xml" })
      expect(result).to eq([message(:misplaced_file, pattern: "*.xml")])
    end

    it "does not apply to office documents" do
      path = build_zip({ "[Content_Types].xml" => "<Types/>" }, name: "table.xlsx")

      expect(validate(path, uploader { validate_zip password: false, required: "*.{xls,xlsx}" })).to be_empty
    end

    it "does not check files that are not ZIP archives" do
      path = write_file("<a/>", name: "data.xml")

      expect(validate(path, uploader { validate_zip required: "*.xml" })).to be_empty
    end
  end

  describe "messages:" do
    it "overrides a message with a string" do
      uploader_class = uploader { validate_zip password: false, messages: { password_forbidden: "No passwords." } }

      expect(validate(encrypted_zip, uploader_class)).to eq(["No passwords."])
    end

    it "passes pattern and name to a lambda" do
      uploader_class = uploader do
        validate_zip required: "*.pdf", messages: { missing_file: ->(name:, pattern:) { "#{name} #{pattern}" } }
      end

      expect(validate(plain_zip, uploader_class)).to eq(["PDF *.pdf"])
    end

    it "accepts a lambda without arguments" do
      uploader_class = uploader { validate_zip password: false, messages: { password_forbidden: -> { "Lambda." } } }

      expect(validate(encrypted_zip, uploader_class)).to eq(["Lambda."])
    end

    it "falls back to I18n for other errors" do
      uploader_class = uploader { validate_zip password: false, messages: { missing_file: "x" } }

      expect(validate(encrypted_zip, uploader_class)).to eq([message(:password_forbidden)])
    end

    it "rejects unknown message keys" do
      uploader_class = uploader { validate_zip password: false, messages: { typo: "x" } }

      expect { validate(plain_zip, uploader_class) }.to raise_error(ArgumentError, /typo/)
    end
  end

  describe ".pattern_name" do
    {
      "*.xml" => "XML",
      "*.{xls,xlsx}" => "XLS/XLSX",
      "data/*.xml" => "data/*.xml",
      "report-*.pdf" => "report-*.pdf"
    }.each do |pattern, name|
      it "returns #{name.inspect} for #{pattern.inspect}" do
        expect(described_class.pattern_name(pattern)).to eq(name)
      end
    end

    it "is used in messages" do
      expect(message(:missing_file, pattern: "*.{xls,xlsx}")).to eq("ZIP archive does not contain a XLS/XLSX file.")
    end
  end

  describe ".extract_one" do
    it "yields the single matching file with its name" do
      path = build_zip("data.xml" => "<a/>", "readme.txt" => "x")

      described_class.extract_one(path, pattern: "*.xml") do |file, name|
        expect([file.read, name, File.extname(file.path)]).to eq(["<a/>", "data.xml", ".xml"])
      end
    end

    it "removes the extracted file afterwards" do
      extracted = described_class.extract_one(plain_zip, pattern: "*.xml") { |file, _| file.path }

      expect(File.exist?(extracted)).to be(false)
    end

    it "accepts a Shrine::UploadedFile" do
      uploaded = Shrine.new(:cache).upload(File.open(plain_zip, "rb"))

      expect(described_class.extract_one(uploaded, pattern: "*.xml") { |file, _| file.read }).to eq("<a/>")
    end

    {
      "encrypted" => [-> { build_zip({ "a.xml" => "x" }, password: "pw") }, :password_forbidden, {}],
      "missing" => [-> { build_zip("a.txt" => "x") }, :missing_file, { pattern: "*.xml" }],
      "misplaced" => [-> { build_zip("dir/a.xml" => "x") }, :misplaced_file, { pattern: "*.xml" }],
      "multiple" => [-> { build_zip("a.xml" => "x", "b.xml" => "y") }, :multiple_files, { pattern: "*.xml" }],
      "not a zip" => [-> { write_file("<a/>", name: "a.xml") }, :invalid_archive, {}]
    }.each do |label, (build, key, options)|
      it "raises for #{label} archives" do
        path = instance_exec(&build)

        expect { described_class.extract_one(path, pattern: "*.xml") { nil } }
          .to raise_error(described_class::Error, message(key, **options))
      end
    end

    it "raises for office documents" do
      path = build_zip({ "[Content_Types].xml" => "<Types/>" }, name: "table.xlsx")

      expect { described_class.extract_one(path, pattern: "*.xlsx") { nil } }
        .to raise_error(described_class::Error, message(:invalid_archive))
    end

    context "with passthrough: true" do
      it "yields a file that is not an archive" do
        path = write_file("<a/>", name: "data.xml")

        result = described_class.extract_one(path, pattern: "*.xml", passthrough: true) { |io, name| [io.read, name] }
        expect(result).to eq(["<a/>", "data.xml"])
      end

      it "yields an office document as it is" do
        path = build_zip({ "[Content_Types].xml" => "<Types/>" }, name: "table.xlsx")

        result = described_class.extract_one(path, pattern: "*.xlsx", passthrough: true) { |io, name| [io.path, name] }
        expect(result).to eq([path, "table.xlsx"])
      end

      it "still extracts from an archive" do
        result = described_class.extract_one(plain_zip, pattern: "*.xml", passthrough: true) { |io, _| io.read }

        expect(result).to eq("<a/>")
      end

      it "uses the original filename of an uploaded file" do
        uploaded = Shrine.new(:cache).upload(File.open(write_file("<a/>", name: "data.xml"), "rb"))

        expect(described_class.extract_one(uploaded, pattern: "*.xml", passthrough: true) { |_, name| name })
          .to eq("data.xml")
      end
    end

    it "accepts a Shrine::UploadedFile from remote storage" do
      uploaded = Shrine.new(:cache).upload(File.open(plain_zip, "rb"))
      remote = Shrine::Storage::Memory.new
      remote.upload(StringIO.new(File.binread(plain_zip)), uploaded.id)
      allow(uploaded).to receive(:storage).and_return(remote)

      expect(described_class.extract_one(uploaded, pattern: "*.xml") { |file, _| file.read }).to eq("<a/>")
    end

    it "raises when the archive understates the entry size" do
      path = understate_sizes(build_zip("a.xml" => "0" * 10_000), 10)

      expect { described_class.extract_one(path, pattern: "*.xml", max_size: 100) { nil } }
        .to raise_error(described_class::Error)
    end

    it "raises when the file exceeds max_size" do
      path = build_zip("a.xml" => "0" * 10_000)

      expect { described_class.extract_one(path, pattern: "*.xml", max_size: 100) { nil } }
        .to raise_error(described_class::Error) { |error| expect(error.key).to eq(:too_large) }
    end
  end
end
