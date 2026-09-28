FROM ruby:4.0.7-alpine AS build

RUN apk add --no-cache build-base postgresql-dev

WORKDIR /app
ENV BUNDLE_DEPLOYMENT=1 BUNDLE_PATH=/usr/local/bundle BUNDLE_WITHOUT=development

COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 && rm -rf /usr/local/bundle/ruby/*/cache


FROM ruby:4.0.7-alpine

RUN apk add --no-cache libpq

WORKDIR /app
ENV BUNDLE_DEPLOYMENT=1 BUNDLE_PATH=/usr/local/bundle BUNDLE_WITHOUT=development APP_ENV=production

COPY --from=build /usr/local/bundle /usr/local/bundle
RUN adduser -D -s /bin/false app
COPY --chown=app:app . .
USER app

EXPOSE 9292
ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bundle", "exec", "puma"]
