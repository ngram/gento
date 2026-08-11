# frozen_string_literal: true

require "cgi"

module Slidescraper
  # HTML entity decoding.
  #
  # CGI.unescapeHTML handles the five predefined entities and numeric
  # references, which leaves the typographic ones that real slide titles and
  # descriptions are full of. Rather than carry the whole HTML5 entity table,
  # translate the handful that actually show up.
  module Entities
    NAMED = {
      "hellip" => "\u2026", "mdash" => "\u2014", "ndash" => "\u2013", "nbsp" => "\u00A0",
      "lsquo" => "\u2018", "rsquo" => "\u2019", "ldquo" => "\u201C", "rdquo" => "\u201D",
      "laquo" => "\u00AB", "raquo" => "\u00BB", "bull" => "\u2022", "middot" => "\u00B7",
      "times" => "\u00D7", "deg" => "\u00B0", "copy" => "\u00A9", "reg" => "\u00AE",
      "trade" => "\u2122"
    }.freeze

    PATTERN = /&(#{Regexp.union(NAMED.keys)});/

    module_function

    def decode(text)
      CGI.unescapeHTML(text.to_s).gsub(PATTERN) { NAMED.fetch(Regexp.last_match(1)) }
    end
  end
end
