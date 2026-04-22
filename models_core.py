from datetime import datetime, timezone

from sqlalchemy import Boolean, Column, DateTime, Float, ForeignKey, Integer, JSON, String, Text
from sqlalchemy.orm import declarative_base, relationship

BaseCore = declarative_base()


class User(BaseCore):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True)
    firebase_uid = Column(String(128), unique=True, index=True, nullable=True)
    username = Column(String(120), unique=True, nullable=False)
    email = Column(String(200), unique=True, nullable=False, index=True)
    role = Column(String(20), default="guest")
    status = Column(String(30), default="Available")
    auth_method = Column(String(20), default="password")
    profile_pic = Column(Text)
    last_login = Column(DateTime, nullable=True)
    profile_setup_completed = Column(Boolean, default=False, nullable=False)
    skill_level = Column(String(24), nullable=True)
    club_affiliation = Column(String(160), nullable=True)


class Wallet(BaseCore):
    __tablename__ = "wallets"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), unique=True)
    available_balance = Column(Float, default=0.0)
    total_topups = Column(Float, default=0.0)
    total_donated = Column(Float, default=0.0)
    token_balance = Column(Float, default=0.0)
    total_purchased = Column(Float, default=0.0)
    last_updated = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    user = relationship("User")


class Transaction(BaseCore):
    __tablename__ = "transactions"

    id = Column(Integer, primary_key=True, index=True)
    amount = Column(Float, nullable=False)
    checkout_request_id = Column(String(100), index=True)
    statuz = Column(String(20), default="PENDING")
    purpose = Column(String(32), default="TOKEN", nullable=False, index=True)
    purpose_ref = Column(String(128), nullable=True, index=True)
    metadata_json = Column(JSON, nullable=True)
    receipt_number = Column(String(50), nullable=True)
    consumed_at = Column(DateTime(timezone=True), nullable=True, index=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)

    user = relationship("User")


class WalletLedger(BaseCore):
    __tablename__ = "wallet_ledger"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    entry_type = Column(String(32), nullable=False, index=True)  # topup, event_donation, subscription_donation, refund, adjustment
    amount = Column(Float, nullable=False)  # positive for topups, negative for deductions
    currency = Column(String(8), nullable=False, default="USD")
    reference_type = Column(String(48), nullable=True, index=True)
    reference_id = Column(String(128), nullable=True, index=True)
    status = Column(String(24), nullable=False, default="completed", index=True)
    metadata_json = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    user = relationship("User")
