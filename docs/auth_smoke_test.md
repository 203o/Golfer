# Auth Smoke Test (Web + FastAPI + Firebase)

## Preconditions
- FastAPI running on `API_BASE_URL` from `.env`
- Firebase web config set in `lib/firebase_options.dart`
- Firebase Admin credentials configured on backend

## 1) Signup (Web)
- Create account with email/password in UI.
- Expect success and no error snackbar.

## 2) Backend User Sync
- Signup flow calls `POST /api/golf/auth/register` with Firebase `id_token`.
- Confirm response includes:
  - `ok: true`
  - `user.id`
  - `user.role` is `guest` after signup

## 3) Authenticated Request
- Call `GET /api/golf/me/subscription` with header:
  - `Authorization: Bearer <firebase_id_token>`
- Expect `200` with `has_subscription` field.

## 4) Subscription Action
- In UI choose a plan and subscribe.
- Expect `POST /api/golf/me/subscription/checkout-complete` success.
- Re-check `/me/subscription` and confirm `status` is `active`.
- Confirm user role is now `subscriber`.

## 5) Score Entry
- Submit a score from score form.
- Expect `POST /api/golf/me/scores` success.

## 6) Logout/Login Cycle
- Logout.
- Login again with same account.
- Re-run `/me/subscription` and `/me/scores` to verify session continuity.

## Common Failure Hints
- `401 Invalid authentication credentials`:
  - missing/expired Bearer token
  - backend Firebase Admin credentials mismatch project
- Signup works but protected calls fail:
  - `/api/golf/auth/register` not called or failed
- `No active draw available`:
  - create/open draw for current month in admin flow
