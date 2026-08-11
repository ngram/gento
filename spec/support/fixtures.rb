# frozen_string_literal: true

require "zlib"

module Fixtures
  ROOT = File.expand_path("../fixtures", __dir__)

  # Reads a captured page.
  #
  # The HTML captures are stored gzipped: they are real pages, kept byte for
  # byte rather than hand-trimmed, and compressing them costs the repository
  # a quarter of what the originals would.
  def fixture(*path)
    file = File.join(ROOT, *path)
    return File.read(file, encoding: "UTF-8") if File.exist?(file)

    Zlib::GzipReader.open("#{file}.gz") { |gz| gz.read.force_encoding("UTF-8") }
  end
end
