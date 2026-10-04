# frozen_string_literal: true

port Integer(ENV.fetch("PORT", 8080))
environment ENV.fetch("RACK_ENV", "production")

threads Integer(ENV.fetch("PUMA_MIN_THREADS", 2)), Integer(ENV.fetch("PUMA_MAX_THREADS", 8))

# Single process on purpose. The deck cache lives in process memory, so extra
# workers would each keep their own copy and multiply requests to the slide
# sites for no gain — a container this small is thread-bound anyway.
workers 0
