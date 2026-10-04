# frozen_string_literal: true

module Gento
  # A minimal HTTP response, so adapters never touch a fetcher-specific object.
  class Response
    attr_reader :status, :headers, :body, :url

    def initialize(status:, body:, url:, headers: {})
      @status = Integer(status)
      @url = url.to_s
      @headers = headers.transform_keys { |key| key.to_s.downcase }.freeze
      @body = Charset.normalize(body, content_type: @headers["content-type"])
      freeze
    end

    def success?
      status.between?(200, 299)
    end

    def content_type
      headers["content-type"]
    end

    def json
      JSON.parse(body)
    rescue JSON::ParserError => e
      raise ExtractionError, "expected JSON from #{url}: #{e.message}"
    end

    def html
      Html.new(body)
    end
  end
end
