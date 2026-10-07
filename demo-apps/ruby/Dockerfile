FROM ruby:3.3-alpine AS builder

WORKDIR /app

RUN apk add --no-cache build-base

COPY Gemfile ./
RUN bundle config set --local without 'development test' && \
    bundle install

FROM ruby:3.3-alpine

WORKDIR /app

# Copy installed gems from builder
COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY app.rb config.ru puma.rb ./

ENV RUBY_SYNC_STDOUT=true
ENV PORT=8085
EXPOSE 8085

# Non-root security context
USER 10001:10001

CMD ["bundle", "exec", "puma", "-C", "puma.rb", "config.ru"]
