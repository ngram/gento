# syntax=docker/dockerfile:1
#
# Build from the REPOSITORY ROOT, not from web/:
#
#   docker build -f web/Dockerfile -t gento-web .
#
# The demo depends on the gem by path, so the build context has to include both.

ARG RUBY_VERSION=3.3

FROM ruby:${RUBY_VERSION}-slim AS build

ENV BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_APP_CONFIG=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test \
    BUNDLE_DEPLOYMENT=1

RUN apt-get update -qq \
    && apt-get install --no-install-recommends -y build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Only what `bundle install` needs to evaluate the path-sourced gemspec, so
# editing application code does not invalidate the dependency layer.
COPY gento.gemspec ./
COPY lib/gento/version.rb lib/gento/
COPY web/Gemfile web/Gemfile.lock web/

RUN cd web && bundle install && bundle clean --force

FROM ruby:${RUBY_VERSION}-slim AS runtime

ENV BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_APP_CONFIG=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test \
    BUNDLE_DEPLOYMENT=1 \
    RACK_ENV=production \
    PORT=8080

RUN groupadd --system --gid 1000 app \
    && useradd --system --uid 1000 --gid app --create-home app

WORKDIR /app

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --chown=app:app gento.gemspec ./
COPY --chown=app:app lib ./lib
COPY --chown=app:app web ./web

USER app
WORKDIR /app/web

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ruby -e 'require "net/http"; \
        url = URI("http://127.0.0.1:#{ENV.fetch("PORT", "8080")}/healthz"); \
        exit(Net::HTTP.get_response(url).code == "200" ? 0 : 1)'

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb", "config.ru"]
