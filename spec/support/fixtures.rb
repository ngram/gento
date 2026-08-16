# frozen_string_literal: true

module Fixtures
  ROOT = File.expand_path("../fixtures", __dir__)

  def fixture(*path)
    File.read(File.join(ROOT, *path), encoding: "UTF-8")
  end
end
