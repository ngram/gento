# frozen_string_literal: true

module Slidescraper
  # A parsed robots.txt, following RFC 9309.
  #
  # The one rule worth implementing carefully is precedence: **the longest
  # matching pattern wins**, not the first one. Google's robots.txt ends with
  #
  #   Allow: /presentation
  #   Disallow: /
  #
  # and a first-match reading would conclude that every Google Slides deck is
  # off limits, which is the opposite of what that file says.
  class Robots
    # A single Allow or Disallow line.
    class Rule
      attr_reader :pattern

      def initialize(pattern, allow:)
        @pattern = pattern
        @allow = allow
        @regexp = self.class.compile(pattern)
        freeze
      end

      def allow?
        @allow
      end

      def covers?(path)
        @regexp.match?(path)
      end

      # RFC 9309 orders rules by the length of the pattern, wildcards included.
      def specificity
        pattern.length
      end

      # `*` stands for any run of characters and `$` anchors the end; every
      # other character is literal.
      def self.compile(pattern)
        anchored = pattern.end_with?("$")
        body = anchored ? pattern[0..-2] : pattern
        source = body.split("*", -1).map { |part| Regexp.escape(part) }.join(".*")
        source += "\\z" if anchored

        Regexp.new("\\A#{source}")
      end
    end

    Group = Struct.new(:agents, :rules, :crawl_delay)

    DIRECTIVES = %w[user-agent allow disallow crawl-delay].freeze
    # A product token runs to the first slash or space: the "slidescraper" of
    # "slidescraper/0.1.0 (+https://...)".
    PRODUCT_TOKEN = %r{\A[^\s/]+}

    attr_reader :groups, :reason

    def initialize(groups = [], reason: nil)
      @groups = groups.freeze
      @reason = reason
      freeze
    end

    class << self
      def parse(body)
        new(Parser.new(body).groups)
      end

      # No robots.txt to obey — the host said so with a 404, or answered with
      # something that is not a robots.txt at all.
      def allow_all
        new
      end

      # RFC 9309 §2.3.1.4: a robots.txt that cannot be read is not permission
      # to crawl. `reason` explains which failure it was.
      def disallow_all(reason: nil)
        new([Group.new(["*"], [Rule.new("/", allow: false)], nil)], reason: reason)
      end

      def product_token(user_agent)
        user_agent.to_s[PRODUCT_TOKEN].to_s.downcase
      end
    end

    def allowed?(path, agent: nil)
      group = group_for(agent)
      return true unless group

      matching = group.rules.select { |rule| rule.covers?(path) }
      return true if matching.empty?

      # Longest pattern wins; an Allow and a Disallow of equal length are a
      # tie the site did not resolve, and RFC 9309 gives those to Allow.
      matching.max_by { |rule| [rule.specificity, rule.allow? ? 1 : 0] }.allow?
    end

    def crawl_delay(agent: nil)
      group_for(agent)&.crawl_delay
    end

    def empty?
      groups.empty?
    end

    private

    # A crawler obeys exactly one group: the one naming it most specifically,
    # falling back to `*`.
    def group_for(agent)
      token = self.class.product_token(agent)

      groups.filter_map { |group| [group, specificity(group, token)] if applies?(group, token) }
            .max_by(&:last)
            &.first
    end

    def applies?(group, token)
      group.agents.any? { |name| name == "*" || (!token.empty? && token.start_with?(name)) }
    end

    def specificity(group, token)
      group.agents.filter_map { |name| name.length if name != "*" && token.start_with?(name) }
           .max || 0
    end

    # robots.txt is a line-oriented `key: value` format. Anything unrecognised
    # is skipped rather than treated as an error, which is also what keeps a
    # page served in place of a robots.txt from parsing into rules.
    class Parser
      attr_reader :groups

      def initialize(body)
        @groups = []
        @current = nil
        @reading_agents = false

        each_directive(body) { |key, value| apply(key, value) }
      end

      private

      def apply(key, value)
        case key
        when "user-agent" then add_agent(value)
        when "allow", "disallow" then add_rule(value, allow: key == "allow")
        when "crawl-delay" then record_crawl_delay(value)
        end
      end

      # Consecutive User-agent lines share one group; a rule line ends the
      # list, so the next User-agent starts a new group.
      def add_agent(value)
        unless @reading_agents && @current
          @current = Group.new([], [], nil)
          @groups << @current
        end

        @current.agents << value.downcase
        @reading_agents = true
      end

      def add_rule(value, allow:)
        @reading_agents = false
        # "Disallow:" with nothing after it lifts the restriction rather than
        # imposing one, so there is no rule to record.
        return if @current.nil? || value.empty?

        @current.rules << Rule.new(value, allow: allow)
      end

      def record_crawl_delay(value)
        @reading_agents = false
        return if @current.nil?

        @current.crawl_delay = Float(value)
      rescue ArgumentError, TypeError
        nil
      end

      def each_directive(body)
        body.to_s.each_line do |line|
          line = line.sub(/#.*/, "").strip
          key, separator, value = line.partition(":")
          next if separator.empty?

          key = key.strip.downcase
          yield key, value.strip if DIRECTIVES.include?(key)
        end
      end
    end
  end
end
