# frozen_string_literal: true

require_relative "lib/gento/version"

Gem::Specification.new do |spec|
  spec.name = "gento"
  spec.version = Gento::VERSION
  spec.authors = ["ngram"]

  spec.summary = "Extract slide page images from slide-sharing services"
  spec.description = <<~DESC
    Turns a Speaker Deck, SlideShare, Docswell or public Google Slides URL into
    the ordered list of page images behind it. Pure Ruby with no runtime
    dependencies and a pluggable HTTP layer, so it runs in slim containers and
    on ruby.wasm as well as on a normal CRuby.
  DESC

  spec.homepage = "https://github.com/ngram/gento"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  # homepage_uri is derived from spec.homepage; setting both makes RubyGems
  # warn about duplicate links.
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "lib/**/*.rb",
    "exe/*",
    "README.md",
    "CHANGELOG.md",
    "LICENSE.txt"
  ]
  spec.bindir = "exe"
  spec.executables = ["gento"]
  spec.require_paths = ["lib"]
end
