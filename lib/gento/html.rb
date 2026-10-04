# frozen_string_literal: true

require "strscan"
require "cgi"
require "json"

module Gento
  # A deliberately small HTML scanner.
  #
  # This is not a DOM parser and does not try to be one. It finds tags by name,
  # reads their attributes, and grabs the raw text of non-void elements, which
  # covers everything the adapters need (meta, link, script, img, title).
  #
  # Why not Nokogiri: it ships a native extension. Staying on pure Ruby keeps
  # the gem usable from slim containers and from ruby.wasm, where compiling
  # libxml is anywhere from painful to impossible.
  class Html
    VOID_ELEMENTS = %w[
      area base br col embed hr img input link meta param source track wbr
    ].freeze

    attr_reader :source

    def initialize(source)
      # Defensive: adapters are the only caller in practice and Response has
      # already normalized, but a caller handing us a raw body should not blow
      # up mid-scan with an encoding error.
      @source = Charset.normalize(source)
      @tags = {}
      @elements = {}
    end

    # Attribute hashes for every occurrence of `name`, in document order.
    #
    # Unlike #elements this never consumes element content, so it still finds
    # tags nested inside another tag of the same name — which ordinary page
    # markup is full of.
    def tags(name)
      @tags[name.to_s.downcase] ||= scan_tags(name.to_s)
    end

    # [attributes, inner_html] pairs for every occurrence of `name`.
    #
    # Only useful for elements that do not nest, such as <script> and <title>;
    # for anything else use #tags.
    def elements(name)
      @elements[name.to_s.downcase] ||= scan_elements(name.to_s)
    end

    # Content of the first <meta> whose name/property/itemprop matches any key.
    def meta(*keys)
      meta_all(*keys).first
    end

    # Content of every matching <meta>, for properties that legitimately repeat.
    def meta_all(*keys)
      wanted = keys.flatten.map { |key| key.to_s.downcase }
      tags("meta").filter_map { |attrs| meta_content(attrs, wanted) }
    end

    # href of the first <link> carrying the given rel token.
    def link(rel)
      wanted = rel.to_s.downcase
      tags("link").each do |attrs|
        tokens = attrs["rel"].to_s.downcase.split(/\s+/)
        return attrs["href"] if tokens.include?(wanted)
      end
      nil
    end

    def title
      inner = elements("title").first&.last
      inner && decode_entities(inner.strip)
    end

    # Every parsed application/ld+json block, with @graph arrays flattened.
    def json_ld
      documents = elements("script").filter_map do |attrs, inner|
        next unless attrs["type"].to_s.downcase.include?("ld+json")

        parse_json(inner)
      end
      documents.flat_map { |doc| flatten_json_ld(doc) }
    end

    # Raw bodies of inline <script> tags, for sites that stash a JSON blob there.
    def inline_scripts
      elements("script").filter_map do |attrs, inner|
        next if attrs.key?("src")

        inner
      end
    end

    # Any absolute URL appearing anywhere in the document, in document order,
    # entity-decoded and deduplicated.
    #
    # Slide hosts put page images wherever suits them: Speaker Deck uses
    # <a href>, Docswell a lazy-loading data attribute, Google Slides a CSS
    # background inside a style attribute. Matching the URL shape across the
    # raw document handles all three, and keeps working when a site moves its
    # images from one element to another.
    ABSOLUTE_URL = %r{https?://[^\s"'<>\\)]+}

    def urls(pattern = //)
      source.scan(ABSOLUTE_URL)
            .map { |url| decode_entities(url) }
            .grep(pattern)
            .uniq
    end

    def decode_entities(text)
      Entities.decode(text)
    end

    private

    # A <meta> carries its key under any of three attributes depending on the
    # vocabulary in use; an empty content is treated as absent.
    def meta_content(attrs, wanted)
      key = attrs["property"] || attrs["name"] || attrs["itemprop"]
      return nil unless key && wanted.include?(key.downcase)

      content = attrs["content"]
      content unless content.nil? || content.empty?
    end

    def scan_tags(name)
      results = []
      scanner = StringScanner.new(@source)
      opening = opening_pattern(name)

      while scanner.skip_until(opening)
        attributes, = scan_attributes(scanner)
        results << attributes
      end

      results
    end

    def scan_elements(name)
      results = []
      scanner = StringScanner.new(@source)
      opening = opening_pattern(name)
      void = VOID_ELEMENTS.include?(name.downcase)

      while scanner.skip_until(opening)
        attributes, self_closing = scan_attributes(scanner)
        inner = void || self_closing ? nil : scan_inner(scanner, name)
        results << [attributes, inner]
      end

      results
    end

    def opening_pattern(name)
      %r{<#{Regexp.escape(name)}(?=[\s>/])}i
    end

    # Consumes the attribute list and the closing `>` of an open tag.
    def scan_attributes(scanner)
      attributes = {}

      loop do
        scanner.skip(/\s+/)
        return [attributes, true] if scanner.scan(%r{/\s*>})
        return [attributes, false] if scanner.scan(">")
        return [attributes, false] if scanner.eos?

        name = scanner.scan(%r{[^\s=/>]+})
        # Never stall: an unexpected byte here would otherwise loop forever.
        next scanner.getch if name.nil?

        scanner.skip(/\s*/)
        attributes[name.downcase] = decode_entities(scan_attribute_value(scanner))
      end
    end

    def scan_attribute_value(scanner)
      return "" unless scanner.scan(/=\s*/)

      if scanner.scan(/"([^"]*)"/) || scanner.scan(/'([^']*)'/)
        scanner[1]
      else
        scanner.scan(/[^\s>]*/).to_s
      end
    end

    # Returns the raw text up to the matching close tag.
    #
    # StringScanner#pos counts bytes while String#[] counts characters, so
    # slicing has to go through byteslice or every multibyte document comes
    # back mangled. Tag boundaries are ASCII, so byte slicing is safe here.
    def scan_inner(scanner, name)
      start = scanner.pos
      closing = %r{</#{Regexp.escape(name)}\s*>}i

      unless scanner.skip_until(closing)
        scanner.terminate
        return byteslice_from(start, @source.bytesize - start)
      end

      byteslice_from(start, scanner.pos - scanner.matched_size - start)
    end

    def byteslice_from(start, length)
      slice = @source.byteslice(start, length).to_s
      slice.valid_encoding? ? slice : slice.scrub
    end

    def parse_json(text)
      JSON.parse(text.to_s)
    rescue JSON::ParserError
      nil
    end

    def flatten_json_ld(doc)
      case doc
      when Array then doc.flat_map { |entry| flatten_json_ld(entry) }
      when Hash then doc.key?("@graph") ? flatten_json_ld(doc["@graph"]) + [doc] : [doc]
      else []
      end
    end
  end
end
