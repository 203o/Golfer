# FastAPI-First Golf Conversion

## Added in this change

- New golf domain models: `models_golf.py`
- New golf API router: `routers/golf.py`
- Router mounted in app: `main.py` (`/api/golf/*`)
- Postgres migration SQL: `sql/2026_04_golf_charity_draw_schema.sql`
- Charity directory patch SQL: `sql/2026_04_charity_directory_and_percentage_patch.sql`

## Core behavior now available

- Public endpoints:
  - `GET /api/golf/public/overview`
  - `GET /api/golf/public/plans`
  - `GET /api/golf/public/charities`
  - `GET /api/golf/public/charities/{charity_ref}`

- Subscriber endpoints:
  - `GET /api/golf/me/subscription`
  - `POST /api/golf/me/subscription/checkout-complete`
  - `POST /api/golf/me/subscription/cancel`
  - `GET /api/golf/me/scores`
  - `POST /api/golf/me/scores`
  - `PUT /api/golf/me/scores/{score_id}`
  - `GET /api/golf/me/charity-selection`
  - `POST /api/golf/me/charity-selection`
  - `POST /api/golf/me/charity-donations`
  - `GET /api/golf/me/participation`
  - `POST /api/golf/me/winner-claims/{entry_id}`

- Admin endpoints:
  - `POST /api/golf/admin/charities`
  - `POST /api/golf/admin/draws`
  - `POST /api/golf/admin/draws/{draw_id}/simulate`
  - `POST /api/golf/admin/draws/{draw_id}/publish`
  - `POST /api/golf/admin/draws/{draw_id}/run`
  - `GET /api/golf/admin/draws/{draw_id}/results`
  - `GET /api/golf/admin/winner-claims`
  - `POST /api/golf/admin/winner-claims/{claim_id}/review`
  - `POST /api/golf/admin/winner-claims/{claim_id}/mark-paid`
  - `GET /api/golf/admin/reports/summary`

## Business rules implemented

- Subscription lifecycle support (`active / inactive / cancelled / lapsed`)
- Active-subscription gating for subscriber features
- Monthly draw model with 5-number match tiers
- 30% of each active subscription's monthly value funds the draw pool
- Users can choose a charity before subscribing and set a default charity contribution percentage
- Minimum charity contribution is 10% of the subscription fee, with higher voluntary percentages allowed
- One-time independent charity donations are supported outside gameplay and subscription checkout
- Public charity directory supports search/filter, featured spotlighting, image galleries, and upcoming charity event profiles
- Monthly pool auto-calculated from active subscriber count and plan mix
- Prize split:
  - 5-match = 40% (+carry in), rollover when no winners
  - 4-match = 35%
  - 3-match = 25%
- Rolling 5-score logic for draw entry number generation
- Winner proof submission and admin review flow
- Payout state transitions (`pending -> paid`)

## Important notes

- This introduces a dedicated golf module with isolated routes for golf and payments.
- `checkout-complete` endpoint is backend-ready but should be called from Stripe webhook-confirmed flow.
- DB migration must be applied before using the new endpoints.
