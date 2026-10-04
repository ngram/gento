# frozen_string_literal: true

module Gento
  # Turns a raw response body into a UTF-8 string we can safely scan.
  #
  # net/http hands back ASCII-8BIT, and Japanese slide decks are the whole
  # point of this library, so guessing the charset properly is not optional.
  module Charset
    DEFAULT = "UTF-8"
    IN_CONTENT_TYPE = /charset\s*=\s*"?([\w-]+)"?/i
    IN_META = /<meta[^>]+charset\s*=\s*["']?([\w-]+)/i
    # A charset declaration must appear early; do not scan a whole document.
    META_SCAN_BYTES = 4096

    module_function

    def normalize(body, content_type: nil)
      body = body.to_s
      name = from_content_type(content_type) || from_meta(body) || DEFAULT
      transcode(body, name)
    end

    def from_content_type(content_type)
      content_type && content_type[IN_CONTENT_TYPE, 1]
    end

    def from_meta(body)
      head = body.byteslice(0, META_SCAN_BYTES).to_s.dup.force_encoding(::Encoding::ASCII_8BIT)
      head[IN_META, 1]
    end

    def transcode(body, name)
      encoding = ::Encoding.find(name)
      decoded = body.dup.force_encoding(encoding)
      decoded = decoded.encode(::Encoding::UTF_8, invalid: :replace, undef: :replace) unless utf8?(encoding)
      decoded.valid_encoding? ? decoded : decoded.scrub
    rescue ArgumentError, ::Encoding::ConverterNotFoundError, ::Encoding::UndefinedConversionError
      body.dup.force_encoding(::Encoding::UTF_8).scrub
    end

    def utf8?(encoding)
      encoding == ::Encoding::UTF_8
    end
  end
end
