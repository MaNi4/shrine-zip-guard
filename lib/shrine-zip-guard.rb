# frozen_string_literal: true

require "shrine"
require "i18n"

require_relative "shrine-zip-guard/version"
require_relative "shrine/plugins/zip_guard"

I18n.load_path += Dir[File.expand_path("../../config/locales/*.yml", __dir__)]
