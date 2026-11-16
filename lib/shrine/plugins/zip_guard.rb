# frozen_string_literal: true

require "shrine"
require "zip"
require "zlib"
require "tempfile"

class Shrine
  module Plugins
    module ZipGuard
      DEFAULTS = {
        max_depth: 3,
        max_entries: 10_000,
        max_nested_size: 100 * 1024 * 1024
      }.freeze

      SIGNATURES = ["PK\x03\x04".b, "PK\x05\x06".b, "PK\x07\x08".b].freeze
      GLOB_FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_CASEFOLD
      CHUNK_SIZE = 64 * 1024
      DOCUMENT_EXTENSIONS = %w[
        .docx .docm .dotx .dotm .xlsx .xlsm .xltx .xltm .pptx .pptm .potx .potm .odt .ods .odp .odg
      ].freeze

      class Error < StandardError
        attr_reader :key, :options

        def initialize(key, **options)
          options = { name: ZipGuard.pattern_name(options[:pattern]) }.merge(options) if options.key?(:pattern)
          @key = key
          @options = options
          super(I18n.t(key, scope: "shrine.zip_guard.errors", **options))
        end
      end

      class << self
        def zip?(path)
          File.open(path, "rb") { |file| SIGNATURES.include?(file.read(4)) }
        end

        def pattern_name(pattern)
          match = pattern.to_s.match(/\A\*\.(?:\{([\w,]+)\}|(\w+))\z/)
          return pattern.to_s unless match

          (match[1] || match[2]).split(",").map(&:upcase).join("/")
        end

        def document?(name)
          DOCUMENT_EXTENSIONS.include?(File.extname(name.to_s).downcase)
        end

        def original_name(file)
          case file
          when Shrine::UploadedFile then file.original_filename || file.id
          when String, Pathname then File.basename(file.to_s)
          else file.respond_to?(:original_filename) ? file.original_filename : File.basename(file.path.to_s)
          end
        end

        def with_path(file, &)
          case file
          when String, Pathname
            yield file.to_s
          when Shrine::UploadedFile
            return yield(file.storage.path(file.id).to_s) if file.storage.respond_to?(:path)

            file.download { |tempfile| yield tempfile.path }
          else
            Shrine.with_file(file) { |io| yield io.path }
          end
        end

        def open_archive(path, &)
          Zip::File.open(path, &)
        rescue Zip::Error, Zlib::Error
          raise Error, :invalid_archive
        end

        def glob(zip, pattern)
          zip.glob(pattern, GLOB_FLAGS).select(&:file?)
        end

        def archive_entry?(entry)
          SIGNATURES.include?(entry.get_input_stream { |input| input.read(4) })
        end

        def copy_entry(entry, output, limit)
          raise Error, :too_large if entry.size > limit

          written = entry.get_input_stream { |input| stream(input, output, limit) }
          output.flush
          written
        end

        def extract_one(file, pattern:, max_size: DEFAULTS[:max_nested_size], passthrough: false, &)
          Extractor.new(pattern:, max_size:, passthrough:).call(file, &)
        end

        private

        def stream(input, output, limit)
          written = 0
          while (chunk = input.read(CHUNK_SIZE))
            written += chunk.bytesize
            raise Error, :too_large if written > limit

            output.write(chunk)
          end
          written
        end
      end

      def self.load_dependencies(uploader, **)
        uploader.plugin :validation
      end

      def self.configure(uploader, **opts)
        unknown = opts.keys - DEFAULTS.keys
        raise ArgumentError, "unknown zip_guard options: #{unknown.join(", ")}" if unknown.any?

        uploader.opts[:zip_guard] = DEFAULTS.merge(uploader.opts[:zip_guard] || {}, opts)
      end

      module AttacherMethods
        CHECKS = { password: [true, false], nested_archives: [true, false] }.freeze
        ERROR_KEYS = %i[
          password_forbidden password_required nested_archive missing_file misplaced_file
          multiple_files too_deep too_large too_many_entries invalid_archive
        ].freeze

        def validate_zip(messages: {}, **checks)
          validate_zip_checks!(checks)
          validate_zip_messages!(messages)
          inspect_zip(checks)
          true
        rescue ZipGuard::Error => e
          errors << zip_error_message(e, messages)
          false
        end

        private

        def inspect_zip(checks)
          checks = checks.except(:required) if ZipGuard.document?(ZipGuard.original_name(file))

          ZipGuard.with_path(file) do |path|
            next unless ZipGuard.zip?(path)

            Inspector.new(**shrine_class.opts[:zip_guard]).call(path, **checks)
          end
        end

        def zip_error_message(error, messages)
          message = messages.fetch(error.key) { return error.message }
          return message unless message.respond_to?(:call)

          message.arity.zero? ? message.call : message.call(**error.options)
        end

        def validate_zip_messages!(messages)
          unknown = messages.keys - ERROR_KEYS
          raise ArgumentError, "unknown validate_zip messages: #{unknown.join(", ")}" if unknown.any?
        end

        def validate_zip_checks!(checks)
          raise ArgumentError, "validate_zip requires :password, :nested_archives or :required" if checks.empty?

          unknown = checks.keys - CHECKS.keys - [:required]
          raise ArgumentError, "unknown validate_zip options: #{unknown.join(", ")}" if unknown.any?

          CHECKS.each do |name, allowed|
            next if !checks.key?(name) || allowed.include?(checks[name])

            raise ArgumentError, "validate_zip #{name}: must be true or false"
          end
        end
      end
    end

    register_plugin(:zip_guard, ZipGuard)
  end
end

require_relative "zip_guard/inspector"
require_relative "zip_guard/extractor"
