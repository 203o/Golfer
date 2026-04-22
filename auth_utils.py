import firebase_admin
import logging
import json
import os
from firebase_admin import credentials, auth
from os import getenv

# --- INITIALIZE FIREBASE ADMIN SDK ---
# Get the path to the service account key file
SERVICE_ACCOUNT_KEY_PATH = getenv(
    "FIREBASE_SERVICE_ACCOUNT_KEY_PATH",
    "credentials/firebase-service-account-key.json",
).strip()

logger = logging.getLogger("Golfer.auth")
firebase_app = None


def _resolve_firebase_credentials():
    # 1) File path (local/dev or Secret Manager mounted file in Cloud Run)
    if SERVICE_ACCOUNT_KEY_PATH and os.path.exists(SERVICE_ACCOUNT_KEY_PATH):
        return credentials.Certificate(SERVICE_ACCOUNT_KEY_PATH)

    # 2) Full service-account JSON passed via env var
    raw_json = (getenv("FIREBASE_SERVICE_ACCOUNT_JSON", "") or "").strip()
    if raw_json:
        data = json.loads(raw_json)
        if "private_key" in data and isinstance(data["private_key"], str):
            data["private_key"] = data["private_key"].replace("\\n", "\n")
        return credentials.Certificate(data)

    # 3) Minimal env var set (project/client email/private key)
    project_id = (getenv("FIREBASE_PROJECT_ID", "") or "").strip()
    client_email = (getenv("FIREBASE_CLIENT_EMAIL", "") or "").strip()
    private_key = (getenv("FIREBASE_PRIVATE_KEY", "") or "").strip()
    if project_id and client_email and private_key:
        data = {
            "type": "service_account",
            "project_id": project_id,
            "private_key": private_key.replace("\\n", "\n"),
            "client_email": client_email,
            "token_uri": "https://oauth2.googleapis.com/token",
        }
        return credentials.Certificate(data)

    # 4) ADC fallback (Cloud Run attached service account)
    return credentials.ApplicationDefault()

# Initialize the app only if it hasn't been initialized already.
if not firebase_admin._apps:
    try:
        cred = _resolve_firebase_credentials()
        firebase_app = firebase_admin.initialize_app(cred)
        logger.info("Firebase Admin SDK initialized successfully")
    except Exception as e:
        logger.error("Failed to initialize Firebase Admin SDK: %s", e)
else:
    # Reuse already initialized default app for startup checks/imports.
    firebase_app = firebase_admin.get_app()

# Export the 'auth' service so other files can use it
fb_auth = auth
