# frozen_string_literal: true

class Shrine
  module Plugins
    module ZipGuard
      class Inspector
        def self.ensure_present!(zip, pattern)
          return if ZipGuard.glob(zip, pattern).any?
          raise Error.new(:misplaced_file, pattern:) if ZipGuard.glob(zip, "**/#{pattern}").any?

          raise Error.new(:missing_file, pattern:)
        end

        def initialize(max_depth:, max_entries:, max_nested_size:)
          @max_depth = max_depth
          @max_entries = max_entries
          @budget = max_nested_size
          @entries = 0
        end

        def call(path, password: nil, nested_archives: nil, required: nil)
          @password = password
          @nested_archives = nested_archives

          inspect_archive(path, depth: 0) do |zip|
            ensure_encrypted!(zip) if password == true
            Array(required).each { |pattern| self.class.ensure_present!(zip, pattern) }
          end
        end

        private

        def inspect_archive(path, depth:)
          ZipGuard.open_archive(path) do |zip|
            count_entries!(zip)
            raise Error, :password_forbidden if @password == false && zip.any?(&:encrypted?)

            yield zip if block_given?
            scan_entries(zip, depth) if @password == false || @nested_archives == false
          end
        end

        def count_entries!(zip)
          @entries += zip.size
          raise Error, :too_many_entries if @entries > @max_entries
        end

        def ensure_encrypted!(zip)
          files = zip.select(&:file?)
          raise Error, :password_required if files.empty? || !files.all?(&:encrypted?)
        end

        def scan_entries(zip, depth)
          zip.each do |entry|
            next unless nested_archive?(entry)

            raise Error, :nested_archive if @nested_archives == false && !ZipGuard.document?(entry.name)

            inspect_nested(entry, depth + 1) if @password == false
          end
        end

        def inspect_nested(entry, depth)
          raise Error, :too_deep if depth > @max_depth

          Tempfile.create("zip_guard", binmode: true) do |tempfile|
            @budget -= ZipGuard.copy_entry(entry, tempfile, @budget)
            inspect_archive(tempfile.path, depth:)
          end
        end

        def nested_archive?(entry)
          entry.file? && !entry.encrypted? && ZipGuard.archive_entry?(entry)
        end
      end
    end
  end
end
