# Deploy Guide: Render (API) + Vercel (Web)

This project is split as:
- Backend API: FastAPI (`main.py`) -> deploy to Render
- Frontend: Flutter Web (`build/web`) -> deploy to Vercel

## 1) Deploy Backend to Render

1. Push this repo to GitHub.
2. In Render:
   - Option A: `New` -> `Blueprint` and point Render at [render.yaml](/C:/Users/VALENTINE/Desktop/Golfer/render.yaml)
   - Option B: `New` -> `Web Service` -> connect repo and use `Docker`
3. Use:
   - Dockerfile: `./Dockerfile`
   - Health check path: `/health`
4. Add required environment variables in Render:
   - `ENVIRONMENT=production`
   - `DATABASE_URL=postgresql+asyncpg://...`
   - `DATABASE_URL_WRITE=postgresql+asyncpg://...`
   - `FIREBASE_PROJECT_ID=...`
   - `FIREBASE_SERVICE_ACCOUNT_JSON={...full Firebase service account JSON...}`
     - This is the recommended cloud setup for Render.
   - `ADMIN_EMAILS=your-admin-email@example.com`
   - `CORS_ALLOW_ORIGINS=https://<your-vercel-domain>.vercel.app,https://<your-custom-domain>`
   - (Optional) M-Pesa vars if needed in production.

5. Deploy. Confirm:
   - `https://<render-service>.onrender.com/health` returns `{"ok":true}`

## 2) Deploy Flutter Web to Vercel

Build locally so Flutter controls the output and stages a Vercel SPA config:

```powershell
.\scripts\build_web_release.ps1 -ApiBaseUrl https://<your-render-service>.onrender.com -StageForVercel
```

Deploy the generated `build/web` folder to Vercel:

```powershell
npm i -g vercel
vercel login
vercel .\build\web --prod
```

When prompted:
- Framework: `Other`
- Output: keep defaults (it uses uploaded static files)

## 3) Firebase Web Auth Production Checks

In Firebase Console:
1. Authentication -> Settings -> Authorized domains
2. Add:
   - `<your-vercel-domain>.vercel.app`
   - your custom domain (if any)

Without this, Google/email auth can fail on production domain.

## 4) Post-Deploy Checks

1. Open Vercel app and test:
   - login/signup
   - loading charities/events
   - subscription mock flow
2. Confirm browser network calls go to Render API URL.
3. If CORS errors appear, update Render `CORS_ALLOW_ORIGINS`.
