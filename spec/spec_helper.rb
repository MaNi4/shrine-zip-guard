# frozen_string_literal: true

require "shrine-zip-guard"
require "shrine/storage/file_system"
require "fileutils"
require "zip"

I18n.load_path += Dir[File.expand_path("../config/locales/*.yml", __dir__)]
I18n.backend.reload!
I18n.locale = :en

Shrine.storages = {
  cache: Shrine::Storage::FileSystem.new("tmp", prefix: "cache"),
  store: Shrine::Storage::FileSystem.new("tmp", prefix: "store")
}

RSpec.configure do |config|
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:suite) do
    FileUtils.rm_rf("tmp")
  end
end
