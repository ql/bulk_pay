# Bulk Pay

Service that lets a firm pay many other firms in one atomic request.

## Run

```bash
docker compose up --build                            # http://localhost:9292, APP_PORT=... to change
docker compose exec app bundle exec rake db:seed     # 3 demo firms
```

Tests (need local Postgres): `bundle exec rspec`

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
