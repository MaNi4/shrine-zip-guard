# frozen_string_literal: true

class Shrine
  module Plugins
    module ZipGuard
      class Extractor
        def initialize(pattern:, max_size:, passthrough:)
          @pattern = pattern
          @max_size = max_size
          @passthrough = passthrough
        end

        def call(file, &)
          name = ZipGuard.original_name(file)
          ZipGuard.with_path(file) do |path|
            next extract(path, &) if ZipGuard.zip?(path) && !ZipGuard.document?(name)
            raise Error, :invalid_archive unless @passthrough

            File.open(path, "rb") { |io| yield io, name }
          end
        end

        private

        def extract(path)
          tempfile, name = extract_entry(path)
          tempfile.rewind
          yield tempfile, name
        ensure
          tempfile&.close!
        end

        def extract_entry(path)
          ZipGuard.open_archive(path) do |zip|
            raise Error, :password_forbidden if zip.any?(&:encrypted?)

            entry = find_single_entry(zip)
            [extract_to_tempfile(entry), entry.name]
          end
        end

        def extract_to_tempfile(entry)
          tempfile = Tempfile.new(["zip_guard", File.extname(entry.name)], binmode: true)
          ZipGuard.copy_entry(entry, tempfile, @max_size)
          tempfile
        rescue StandardError
          tempfile&.close!
          raise
        end

        def find_single_entry(zip)
          entries = ZipGuard.glob(zip, @pattern)
          Inspector.ensure_present!(zip, @pattern) if entries.empty?
          raise Error.new(:multiple_files, pattern: @pattern) if entries.size > 1

          entries.first
        end
      end
    end
  end
end
