# Tournament V1 API

Base prefix: `/api/tournament`

## Round Lifecycle
- `POST /rounds` create draft round
- `PUT /rounds/{round_id}/holes/{hole_no}` add/update hole score
- `GET /rounds/{round_id}` fetch round + progress + totals preview
- `POST /rounds/{round_id}/submit` submit with marker id (locks editing)
- `POST /rounds/{round_id}/marker-confirm` marker verifies submitted round
- `POST /rounds/{round_id}/reject` marker/admin rejects round
- `POST /rounds/{round_id}/lock` admin locks verified round (immutable for analytics)

## Rating + Metrics
- `POST /ratings/recompute?user_id=...` recompute snapshot + rating
- `GET /players/{user_id}/metrics` get latest metric snapshot
- `GET /players/{user_id}/rating` get latest player rating
- `GET /players/{user_id}/trust-score` get trust score

## Fraud
- `GET /fraud-flags?status=open` admin list flags

## Team Draw
- `POST /team-draw/generate` generate balanced teams from rated players
- `GET /team-draw/{run_id}` fetch generated teams

## Notes
- Current V1 draw generation supports `balanced_sum` only.
- Role guards use existing roles:
  - `admine` for admin-only actions
  - `subscriber` and `admine` for player actions
