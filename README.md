# Golfer

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Deep Link Setup (Cloud Run Host)

This repo is configured for app links/universal links with:

- Android host paths: `/links/p/*` and `/p/*`
- iOS associated domains: `applinks:app.shulox.com`
- Backend endpoints:
  - `/.well-known/assetlinks.json`
  - `/.well-known/apple-app-site-association`

### Replace placeholders before production

Set these environment variables when deploying backend:

- `ANDROID_APP_PACKAGE` (default: `com.herberkom.Golfer`)
- `ANDROID_APP_SHA256_FINGERPRINTS` (comma-separated SHA256 cert fingerprints)
- `IOS_TEAM_ID` (Apple Team ID)
- `IOS_BUNDLE_ID` (default: `com.herberkom.Golfer`)

Example Cloud Run deploy:

```bash
gcloud run deploy Golfer-api \
  --source . \
  --project Golfer-a4ad7 \
  --region europe-west1 \
  --platform managed \
  --allow-unauthenticated \
  --set-env-vars ANDROID_APP_PACKAGE=com.herberkom.Golfer,ANDROID_APP_SHA256_FINGERPRINTS=REPLACE_WITH_RELEASE_SHA256_FINGERPRINT,IOS_TEAM_ID=REPLACE_WITH_APPLE_TEAM_ID,IOS_BUNDLE_ID=com.herberkom.Golfer
```

### Verify after deploy

- `https://app.shulox.com/.well-known/assetlinks.json`
- `https://app.shulox.com/.well-known/apple-app-site-association`

## Cloud Scheduler Setup

Production task endpoints already exist in `routers/scheduler.py`:

- `/tasks/session-cleanup`
- `/tasks/health-check`
- `/tasks/nightly`

Use the PowerShell setup script to upsert the recommended jobs in Cloud Scheduler:

```powershell
.\scripts\setup_cloud_scheduler.ps1
```

Defaults:

- Project: `Golfer-a4ad7`
- Region: `europe-west1`
- Service: `Golfer-api`
- Time zone: `Africa/Nairobi`

The script reads `INTERNAL_API_TOKEN` from Secret Manager and configures:

- `Golfer-session-cleanup-midnight` at `0 0 * * *`
- `Golfer-health-check-daily` at `5 0 * * *`
- `Golfer-nightly-maintenance` at `55 23 * * *`
