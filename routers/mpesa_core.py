import base64
import logging
from datetime import datetime, timezone
from typing import Any, Optional

import requests
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from requests.auth import HTTPBasicAuth
from sqlalchemy.orm import Session

from database import get_sync_db
from dependencies import get_current_user
from models_core import Transaction, User, Wallet
from settings import Settings

router = APIRouter(prefix="/api/v1/mpesa", tags=["M-Pesa"])
settings = Settings()
logger = logging.getLogger("golf.mpesa")


class StkPushRequest(BaseModel):
    phone_number: str = Field(min_length=10, max_length=16)
    amount: int = Field(ge=1, le=100000)
    purpose: str = Field(default="TOKEN", max_length=32)
    purpose_ref: str | None = Field(default=None, max_length=128)
    transaction_desc: str | None = Field(default=None, max_length=120)


class StkPushResponse(BaseModel):
    checkout_request_id: str
    merchant_request_id: Optional[str] = None
    customer_message: str


def _normalize_phone(phone_number: str) -> str:
    clean_phone = (phone_number or "").replace("+", "").strip()
    if clean_phone.startswith("0"):
        clean_phone = "254" + clean_phone[1:]
    if not clean_phone.startswith("254") or len(clean_phone) != 12 or not clean_phone.isdigit():
        raise HTTPException(status_code=400, detail="Phone number must be a valid Kenyan number")
    return clean_phone


def _daraja_access_token() -> str:
    oauth_url = f"{settings.daraja_base_url}/oauth/v1/generate?grant_type=client_credentials"
    response = requests.get(
        oauth_url,
        auth=HTTPBasicAuth(settings.DARAJA_CONSUMER_KEY, settings.DARAJA_CONSUMER_SECRET),
        timeout=(10, 20),
    )
    if response.status_code >= 400:
        raise HTTPException(status_code=502, detail="Unable to authenticate with M-Pesa provider")

    token = response.json().get("access_token")
    if not token:
        raise HTTPException(status_code=502, detail="Invalid M-Pesa OAuth response")
    return token


def _daraja_password() -> tuple[str, str]:
    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    data_to_encode = settings.DARAJA_SHORTCODE + settings.DARAJA_PASSKEY + timestamp
    password = base64.b64encode(data_to_encode.encode()).decode()
    return password, timestamp


def _metadata_value(items: list[dict[str, Any]], name: str) -> Any:
    for item in items:
        if str(item.get("Name", "")).lower() == name.lower():
            return item.get("Value")
    return None


@router.post("/stk/push", response_model=StkPushResponse)
async def stk_push(
    payload: StkPushRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_sync_db),
) -> StkPushResponse:
    phone = _normalize_phone(payload.phone_number)
    token = _daraja_access_token()
    password, timestamp = _daraja_password()

    stk_url = f"{settings.daraja_base_url}/mpesa/stkpush/v1/processrequest"
    callback_url = settings.DARAJA_CALLBACK_URL
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

    request_payload = {
        "BusinessShortCode": settings.DARAJA_SHORTCODE,
        "Password": password,
        "Timestamp": timestamp,
        "TransactionType": "CustomerPayBillOnline",
        "Amount": payload.amount,
        "PartyA": phone,
        "PartyB": settings.DARAJA_SHORTCODE,
        "PhoneNumber": phone,
        "CallBackURL": callback_url,
        "AccountReference": f"golf{current_user.id}",
        "TransactionDesc": payload.transaction_desc or "Golf Charity Payment",
    }

    response = requests.post(stk_url, json=request_payload, headers=headers, timeout=(10, 25))
    if response.status_code >= 400:
        raise HTTPException(status_code=502, detail="M-Pesa STK push failed")

    response_json = response.json()
    checkout_request_id = response_json.get("CheckoutRequestID")
    if not checkout_request_id:
        raise HTTPException(status_code=502, detail="M-Pesa did not return CheckoutRequestID")

    tx = Transaction(
        user_id=current_user.id,
        amount=float(payload.amount),
        checkout_request_id=checkout_request_id,
        statuz="PENDING",
        purpose=(payload.purpose or "TOKEN").upper(),
        purpose_ref=(payload.purpose_ref or "").strip() or None,
        metadata_json={"source": "golf_stk_push", "phone": phone},
    )
    db.add(tx)
    db.commit()

    return StkPushResponse(
        checkout_request_id=checkout_request_id,
        merchant_request_id=response_json.get("MerchantRequestID"),
        customer_message=response_json.get("CustomerMessage", "STK push sent"),
    )


@router.post("/callback")
async def stk_callback(request: Request, db: Session = Depends(get_sync_db)) -> dict[str, str]:
    payload = await request.json()

    stk_callback_data = (
        payload.get("Body", {})
        .get("stkCallback", {})
    )

    checkout_request_id = stk_callback_data.get("CheckoutRequestID")
    result_code = stk_callback_data.get("ResultCode")
    metadata_items = stk_callback_data.get("CallbackMetadata", {}).get("Item", [])

    if not checkout_request_id:
        return {"ResultCode": "0", "ResultDesc": "Ignored"}

    tx = db.query(Transaction).filter(Transaction.checkout_request_id == checkout_request_id).first()
    if not tx:
        return {"ResultCode": "0", "ResultDesc": "No matching transaction"}

    if int(result_code or 1) == 0:
        receipt = _metadata_value(metadata_items, "MpesaReceiptNumber")
        amount = _metadata_value(metadata_items, "Amount")

        tx.statuz = "SUCCESS"
        tx.receipt_number = str(receipt) if receipt else tx.receipt_number
        tx.metadata_json = {
            **(tx.metadata_json or {}),
            "callback_received": True,
            "raw": stk_callback_data,
        }

        if (tx.purpose or "").upper() == "TOKEN":
            wallet = db.query(Wallet).filter(Wallet.user_id == tx.user_id).first()
            if wallet is None:
                wallet = Wallet(user_id=tx.user_id, token_balance=0.0, total_purchased=0.0)
                db.add(wallet)

            # 1 KES = 1 token for now
            credit = float(amount or tx.amount or 0)
            wallet.token_balance = float(wallet.token_balance or 0) + credit
            wallet.total_purchased = float(wallet.total_purchased or 0) + credit
    else:
        tx.statuz = "FAILED"
        tx.metadata_json = {
            **(tx.metadata_json or {}),
            "callback_received": True,
            "raw": stk_callback_data,
        }

    db.add(tx)
    db.commit()

    return {"ResultCode": "0", "ResultDesc": "Accepted"}
