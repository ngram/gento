# frozen_string_literal: true

require "optparse"
require "json"

module Slidescraper
  # `slidescraper <URL>` — prints the deck as JSON, or one image URL per line.
  class CLI
    EXIT_SUCCESS = 0
    EXIT_FAILURE = 1
    EXIT_USAGE = 2

    def self.start(argv, stdout: $stdout, stderr: $stderr)
      new(stdout: stdout, stderr: stderr).run(argv)
    end

    def initialize(stdout: $stdout, stderr: $stderr)
      @stdout = stdout
      @stderr = stderr
      @options = { format: :json, pretty: true }
    end

    def run(argv)
      urls = parser.parse(argv.dup)

      if urls.empty?
        @stderr.puts parser.help
        return EXIT_USAGE
      end

      scrape_all(urls)
    rescue OptionParser::ParseError => e
      @stderr.puts "slidescraper: #{e.message}"
      EXIT_USAGE
    end

    private

    def scrape_all(urls)
      client = Client.new(fetcher: build_fetcher)
      status = EXIT_SUCCESS

      urls.each do |url|
        emit(client.scrape(url))
      rescue Error => e
        @stderr.puts "slidescraper: #{url}: #{e.message}"
        status = EXIT_FAILURE
      end

      status
    end

    def emit(deck)
      case @options[:format]
      when :urls then deck.slides.each { |slide| @stdout.puts slide.url }
      else @stdout.puts serialize(deck)
      end
    end

    def serialize(deck)
      @options[:pretty] ? JSON.pretty_generate(deck.to_h) : deck.to_h.to_json
    end

    def build_fetcher
      NetHttpFetcher.new(**{
        user_agent: @options[:user_agent],
        read_timeout: @options[:timeout]
      }.compact)
    end

    def parser
      @parser ||= OptionParser.new do |opts|
        opts.banner = "Usage: slidescraper [options] URL [URL...]"
        opts.separator ""
        opts.separator "Supported providers: #{Slidescraper.providers.join(', ')}"
        opts.separator ""

        define_output_options(opts)
        define_request_options(opts)
        define_meta_options(opts)
      end
    end

    def define_output_options(opts)
      opts.on("-f", "--format FORMAT", %i[json urls],
              "Output format: json (default) or urls") do |format|
        @options[:format] = format
      end

      opts.on("--[no-]pretty", "Pretty-print JSON output (default: on)") do |pretty|
        @options[:pretty] = pretty
      end
    end

    def define_request_options(opts)
      opts.on("-t", "--timeout SECONDS", Integer, "Read timeout per request") do |timeout|
        @options[:timeout] = timeout
      end

      opts.on("-A", "--user-agent STRING", "User-Agent to send") do |agent|
        @options[:user_agent] = agent
      end
    end

    def define_meta_options(opts)
      opts.on("-h", "--help", "Show this message") do
        @stdout.puts opts
        exit EXIT_SUCCESS
      end

      opts.on("-v", "--version", "Show the version") do
        @stdout.puts Slidescraper::VERSION
        exit EXIT_SUCCESS
      end
    end
  end
end
