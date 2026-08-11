# frozen_string_literal: true

require "shrine"
require "zip"

class Shrine
  module Plugins
    module ZipGuard
      class Error < StandardError; end
      class EncryptedZipError < Error; end

      class MissingFileError < Error
        attr_reader :pattern

        def initialize(pattern)
          @pattern = pattern
          super("Archive does not contain required file matching '#{pattern}'")
        end
      end

      class << self
        def with_zip(original, required_files: nil, &)
          return yield(nil) unless zip?(original)

          Zip::File.open(original.path) do |zip_file|
            raise EncryptedZipError if zip_file.any?(&:encrypted?)

            if required_files
              Array(required_files).each do |pattern|
                raise MissingFileError, pattern unless zip_file.glob(pattern).any?
              end
            end

            yield zip_file
          end
        end

        private

        def zip?(original)
          return false unless original.respond_to?(:path)

          File.extname(original.path).downcase == ".zip"
        end
      end

      module AttacherMethods
        def create_derivatives(*args, **options, &)
          super
        rescue ZipGuard::EncryptedZipError
          errors << I18n.t(error_message_key("password_protected"))
          {}
        rescue ZipGuard::MissingFileError => e
          errors << I18n.t(error_message_key("missing_file"), pattern: e.pattern)
          {}
        rescue StandardError => e
          handle_error(e)
          {}
        end

        private

        def error_message_key(base_key)
          uploader_name = shrine_class.name
          return "shrine.zip_guard.#{base_key}" unless uploader_name

          custom_key = "shrine.zip_guard.errors.#{underscore(uploader_name)}.#{base_key}"
          I18n.t(custom_key, default: nil) ? custom_key : "shrine.zip_guard.#{base_key}"
        end

        def underscore(class_name)
          class_name
            .gsub("::", "/")
            .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .tr("-", "_")
            .downcase
        end

        def handle_error(error)
          fallback = shrine_class.opts[:zip_guard][:fallback]

          if fallback
            fallback.call(error, self)
          else
            report_error(error)
            errors << I18n.t(error_message_key("processing_failed"))
          end
        end

        def report_error(error)
          return unless defined?(Rails) && Rails.respond_to?(:error) && Rails.error.respond_to?(:report)

          Rails.error.report(error)
        end
      end

      def self.configure(uploader, **opts)
        uploader.opts[:zip_guard] = {
          fallback: opts[:fallback],
          required_files: opts[:required_files]
        }

        return unless opts[:required_files]

        uploader::Attacher.derivatives do |original|
          ZipGuard.with_zip(original, required_files: opts[:required_files]) do |_zip_file|
            {}
          end
        end
      end

      def self.load_dependencies(uploader, **)
        uploader.plugin :derivatives
        uploader.plugin :validation
      end
    end

    register_plugin(:zip_guard, ZipGuard)
  end
end
