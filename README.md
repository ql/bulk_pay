# Bulk Pay

Service that lets a firm pay many other firms in one atomic request.

## Runs on

- Ruby 4.0.7 (`.ruby-version`), Bundler 4
- PostgreSQL 17 in Docker, also tested on 15; 9.6+ required
- Rack 3 + Puma 7, ActiveRecord 8.1, no Rails
- Docker with Compose v2 to run it, or local Ruby + Postgres (with `libpq` for the `pg` gem)

## Run

```bash
docker compose up --build                            # http://localhost:9292, APP_PORT=... to change
docker compose exec app bundle exec rake db:seed     # 3 demo firms
```

Without Docker: `bundle install && bundle exec rake db:prepare && bundle exec puma`

Tests: `bundle exec rspec` - needs local Postgres with a `bulk_pay` user allowed to create databases,
the suite drops and recreates `bulk_pay_test` on every run.

| Env var | Default | |
|---|---|---|
| `APP_ENV` | `development` | `development` / `test` / `production` database |
| `DB_HOST`, `DB_PORT` | `localhost`, `5432` | |
| `DB_USER`, `DB_PASS` | `bulk_pay`, empty | |
| `MAX_THREADS` | `5` | Puma threads and DB pool size |
| `WEB_CONCURRENCY` | `0` | Puma workers |
| `PORT` | `9292` | port inside the container; `APP_PORT` is the host port in compose |
| `LOCK_TIMEOUT`, `STATEMENT_TIMEOUT` | `3s`, `5s` | waiting for firm row locks, beyond that 503 |

## API

`POST /bulk_payments`

The `Idempotency-Key` header is **required**. Use a new key for every new request and the same key when retrying it,
so a retry never pays twice. A key made from the current time:

```bash
KEY="$(date +%Y%m%d%H%M%S)-$RANDOM"
```

```bash
curl -i -X POST localhost:9292/bulk_payments \
  -H "Idempotency-Key: $KEY" \
  -d '{
    "payer_firm_uuid": "3f1c9a2e-7b4d-4c1e-9a55-2d8e6f0b7c41",
    "payments": [
      { "amount": "6250",    "payee_firm_uuid": "e5f18b3c-2a9d-4c07-8e6b-1d4a7f9c3b25", "description": "Overflow returns, August 2026" },
      { "amount": "1200.75", "payee_firm_uuid": "8b2e4c71-0d3a-4f6e-b1c9-5a7d2e9f4c10", "description": "Bookkeeping cleanup, 3 clients" }
    ]
  }'
```

`amount` is a string in dollars with up to 2 decimals, `description` is up to 500 chars, up to 1000 payments per request.

| Status | Meaning |
|---|---|
| 201 | Paid. A repeated key returns 201 with `Idempotent-Replayed: true` and charges nothing |
| 400 | Invalid body or missing / invalid `Idempotency-Key` |
| 404 | Unknown firm |
| 422 | Insufficient balance (nothing is paid), or key already used for a different request |
| 503 | Firms are busy, retry with the same key |

## Further work

This solution is deliberately minimalistic. In order to deploy it as a production service following things should be implemented:
 - Authentication. It should be probably implemented as outer layer indpendent from this logic and providing just some signal that request was already authenticated
 - Monitoring - Sentry or something similar for exception handling, NewRelic-style instrumentation to see performance and DB queries
 - Load testing - this service should be tested in thousands of firms sending requests to each other simultaneously (simulating congestion at the end of accounting period)
 - Improving API accessibility, i.e. providing full list of payments or at least their count

## Development process

see NOTES.md
