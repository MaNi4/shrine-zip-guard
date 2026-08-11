# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "securerandom"
require "stringio"

RSpec.describe Shrine::Plugins::ZipGuard do
  def zip_file(entries)
    io = StringIO.new

    Zip::OutputStream.write_buffer(io) do |zos|
      entries.each do |name, content|
        zos.put_next_entry(name)
        zos.write(content)
      end
    end

    io.rewind
    io
  end

  def encrypted_zip_file(password: "password")
    plain = Tempfile.new(["plain", ".xml"])
    plain.write("<root/>")
    plain.close

    encrypted_path = File.join(Dir.tmpdir, "encrypted-#{SecureRandom.hex}.zip")

    system("zip", "-j", "-P", password, encrypted_path, plain.path, out: File::NULL, err: File::NULL)

    File.open(encrypted_path, binmode: true)
  end

  def corrupt_zip_file
    Tempfile.new(["corrupt", ".zip"], binmode: true).tap do |t|
      t.write("this is not a zip file")
      t.rewind
    end
  end

  def tempfile_from_zip(zip_io)
    tempfile = Tempfile.new(["test", ".zip"], binmode: true)
    tempfile.write(zip_io.read)
    tempfile.rewind
    tempfile
  end

  describe ".with_zip" do
    it "yields zip file for valid zip" do
      file = tempfile_from_zip(zip_file("file.xml" => "<root/>"))

      yielded = false
      described_class.with_zip(file, required_files: ["*.xml"]) do |zip_file|
        yielded = true
        expect(zip_file.glob("*.xml")).not_to be_empty
      end

      expect(yielded).to be true
    end

    it "raises EncryptedZipError for password protected zip" do
      file = encrypted_zip_file

      expect do
        described_class.with_zip(file) { nil }
      end.to raise_error(described_class::EncryptedZipError)
    end

    it "raises MissingFileError when required file is missing" do
      file = tempfile_from_zip(zip_file("file.txt" => "content"))

      expect do
        described_class.with_zip(file, required_files: ["*.xml"]) { nil }
      end.to raise_error(
        described_class::MissingFileError,
        "Archive does not contain required file matching '*.xml'"
      )
    end

    it "passes when required file exists at nested level" do
      file = tempfile_from_zip(zip_file("data/nested/file.xml" => "<root/>"))

      expect do
        described_class.with_zip(file, required_files: ["**/*.xml"]) { nil }
      end.not_to raise_error
    end

    it "accepts required_files as string" do
      file = tempfile_from_zip(zip_file("file.xml" => "<root/>"))

      expect do
        described_class.with_zip(file, required_files: "*.xml") { nil }
      end.not_to raise_error
    end
  end

  describe "error handling in derivatives" do
    let(:uploader_with_derivatives) do
      Class.new(Shrine) do
        plugin :zip_guard

        self::Attacher.derivatives do |original|
          Shrine::Plugins::ZipGuard.with_zip(original, required_files: ["*.xml"]) do
            {}
          end
        end
      end
    end

    let(:attacher) { uploader_with_derivatives::Attacher.new }

    it "adds friendly error for encrypted zip" do
      file = encrypted_zip_file
      attacher.attach(file)
      result = attacher.create_derivatives

      expect(result).to eq({})
      expect(attacher.errors).to include("ZIP file is password protected. Please upload an unprotected file.")
    end

    it "adds friendly error for missing file" do
      file = tempfile_from_zip(zip_file("file.txt" => "content"))
      attacher.attach(file)
      result = attacher.create_derivatives

      expect(result).to eq({})
      expect(attacher.errors).to include("Archive does not contain required file matching '*.xml'.")
    end

    it "returns empty hash on encrypted zip error" do
      file = encrypted_zip_file
      attacher.attach(file)
      result = attacher.create_derivatives

      expect(result).to be_a(Hash)
      expect(result).to eq({})
    end

    it "returns empty hash on missing file error" do
      file = tempfile_from_zip(zip_file("file.txt" => "content"))
      attacher.attach(file)
      result = attacher.create_derivatives

      expect(result).to be_a(Hash)
      expect(result).to eq({})
    end
  end

  describe "StandardError handling" do
    it "catches StandardError and adds processing_failed message" do
      uploader = Class.new(Shrine) do
        plugin :zip_guard

        self::Attacher.derivatives do |_original|
          raise StandardError, "Unexpected failure"
        end
      end

      file = tempfile_from_zip(zip_file("file.xml" => "<root/>"))
      attacher = uploader::Attacher.new
      attacher.attach(file)
      result = attacher.create_derivatives

      expect(result).to eq({})
      expect(attacher.errors).to include("File could not be processed. Please try again or contact support.")
    end

    it "calls fallback for corrupt zip" do
      captured = nil
      uploader = Class.new(Shrine) do
        plugin :zip_guard,
               fallback: lambda { |error, a|
                 captured = error
                 a.errors << "Custom: #{error.class}"
               }

        self::Attacher.derivatives do |original|
          Shrine::Plugins::ZipGuard.with_zip(original) { |_| {} }
        end
      end

      file = corrupt_zip_file
      attacher = uploader::Attacher.new
      attacher.attach(file)
      result = attacher.create_derivatives

      expect(result).to eq({})
      expect(captured).to be_a(Zip::Error).or be_a(Errno::ENOENT)
      expect(attacher.errors).to include(/Custom:/)
    end

    it "calls fallback for custom ZipGuard::Error subclass" do
      custom_error_class = Class.new(described_class::Error)
      captured_error = nil

      uploader = Class.new(Shrine) do
        plugin :zip_guard,
               fallback: lambda { |error, a|
                 captured_error = error
                 a.errors << "Custom handled: #{error.message}"
               }

        self::Attacher.derivatives do |_original|
          raise custom_error_class, "Custom app error"
        end
      end

      file = tempfile_from_zip(zip_file("file.xml" => "<root/>"))
      attacher = uploader::Attacher.new
      attacher.attach(file)
      result = attacher.create_derivatives

      expect(result).to eq({})
      expect(captured_error).to be_a(custom_error_class)
      expect(captured_error.message).to eq("Custom app error")
      expect(attacher.errors).to include("Custom handled: Custom app error")
    end
  end

  describe "automatic required_files validation" do
    let(:uploader_with_auto_validation) do
      Class.new(Shrine) do
        plugin :zip_guard, required_files: ["*.xml"]
      end
    end

    let(:attacher) { uploader_with_auto_validation::Attacher.new }

    it "validates required files automatically" do
      file = tempfile_from_zip(zip_file("file.txt" => "content"))
      attacher.attach(file)
      result = attacher.create_derivatives

      expect(result).to eq({})
      expect(attacher.errors).to include("Archive does not contain required file matching '*.xml'.")
    end
  end

  describe "custom error key based on uploader name" do
    let(:uploader) do
      custom_class = Class.new(Shrine) do
        plugin :zip_guard
      end
      custom_class.define_singleton_method(:name) { "CustomUploader" }
      custom_class
    end

    let(:attacher) { uploader::Attacher.new }

    it "uses uploader-specific key when translation exists" do
      allow(I18n).to receive(:t).with(
        "shrine.zip_guard.errors.custom_uploader.missing_file", default: nil
      ).and_return("found")

      expect(attacher.send(:error_message_key, "missing_file")).to eq(
        "shrine.zip_guard.errors.custom_uploader.missing_file"
      )
    end

    it "falls back to default key when translation is missing" do
      allow(I18n).to receive(:t).with(
        "shrine.zip_guard.errors.custom_uploader.missing_file", default: nil
      ).and_return(nil)

      expect(attacher.send(:error_message_key, "missing_file")).to eq(
        "shrine.zip_guard.missing_file"
      )
    end
  end

  describe "custom fallback" do
    let(:custom_error_class) do
      Class.new(described_class::Error)
    end

    it "uses default fallback and adds processing_failed error" do
      error_class = custom_error_class
      uploader_with_custom_error = Class.new(Shrine) do
        plugin :zip_guard

        self::Attacher.derivatives do |_original|
          raise error_class, "Something went wrong"
        end
      end

      attacher = uploader_with_custom_error::Attacher.new
      file = tempfile_from_zip(zip_file("file.xml" => "<root/>"))
      attacher.attach(file)
      result = attacher.create_derivatives

      expect(result).to eq({})
      expect(attacher.errors).to include("File could not be processed. Please try again or contact support.")
    end

    it "calls custom fallback when configured" do
      captured_error = nil
      error_class = custom_error_class

      uploader_with_fallback = Class.new(Shrine) do
        plugin :zip_guard,
               fallback: lambda { |error, attacher_obj|
                 captured_error = error
                 attacher_obj.errors << "Custom error: #{error.message}"
               }

        self::Attacher.derivatives do |_original|
          raise error_class, "Something went wrong"
        end
      end

      attacher = uploader_with_fallback::Attacher.new
      file = tempfile_from_zip(zip_file("file.xml" => "<root/>"))
      attacher.attach(file)
      result = attacher.create_derivatives

      expect(result).to eq({})
      expect(captured_error).to be_a(error_class)
      expect(attacher.errors).to include("Custom error: Something went wrong")
    end
  end
end
