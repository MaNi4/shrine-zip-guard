# frozen_string_literal: true

require_relative "lib/shrine-zip-guard/version"

Gem::Specification.new do |spec|
  spec.name = "shrine-zip-guard"
  spec.version = ShrineZipGuard::VERSION
  spec.authors = ["Martin Dobrovodský"]
  spec.email = ["dobrovodsky.martin@gmail.com"]

  spec.summary = "Shrine validation that rejects password-protected and nested ZIP archives"
  spec.description = "Shrine validate_zip helper for password, nested archive and required file checks, " \
                     "plus a size-limited single-file ZIP extractor."
  spec.homepage = "https://github.com/MaNi4/shrine-zip-guard"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "i18n", "~> 1.0"
  spec.add_dependency "rubyzip", ">= 3.0", "< 4.0"
  spec.add_dependency "shrine", ">= 3.0", "< 4.0"
end
