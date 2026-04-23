from __future__ import annotations

import base64
import math
import uuid
from datetime import datetime, timezone, timedelta
from decimal import Decimal
from statistics import pstdev
from typing import Any

import requests
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from requests.auth import HTTPBasicAuth
from sqlalchemy import and_, cast, delete, func, or_, select, String
from sqlalchemy.exc import IntegrityError, ProgrammingError
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from dependencies import get_current_user, get_current_user_optional, require_admin, require_user
from models_core import Transaction, User, Wallet, WalletLedger
from models_golf import (
    GolfCharity,
    GolfCharityDonation,
    GolfDraw,
    GolfDrawEntry,
    GolfScore,
    GolfUserCharitySetting,
    TournamentChallengeParticipant,
    TournamentChallengeSession,
    TournamentCourse,
    TournamentCourseHole,
    TournamentEvent,
    TournamentEventDonation,
    TournamentEventParticipant,
    TournamentEventUnlock,
    TournamentFriendRequest,
    TournamentFraudFlag,
    TournamentInboxMessage,
    TournamentPlayerMetricSnapshot,
    TournamentPlayerProfile,
    TournamentPlayerRating,
    TournamentRound,
    TournamentRoundAuditEvent,
    TournamentRoundHole,
    TournamentRoundVerification,
    TournamentScoreboardEntry,
    TournamentSessionScore,
    TournamentSessionScoreHole,
    TournamentTeamAssignment,
    TournamentTeamDrawRun,
)
from settings import Settings

router = APIRouter(prefix="/api/tournament", tags=["Tournament"])
settings = Settings()

DEFAULT_EVENT_CONFIGS: list[dict[str, Any]] = [
    {
        "key": "solo_challenge",
        "event_type": "solo",
        "stored_event_type": "group_challenge",
        "title": "Solo Challenge",
        "description": "Play and submit your own round without needing a marker",
        "min_donation_cents": 200,
        "unlock_mode": "window_access",
        "window_days": 7,
        "max_participants": 1,
    },
    {
        "key": "one_on_one",
        "event_type": "one_on_one",
        "title": "1v1 Duel",
        "description": "Two players, head-to-head",
        "min_donation_cents": 200,
        "unlock_mode": "window_access",
        "window_days": 7,
    },
    {
        "key": "skill_challenge",
        "event_type": "skill_challenge",
        "title": "Skill Challenge",
        "description": "Closest-to-target, putt streak, low-3-hole score",
        "min_donation_cents": 500,
        "unlock_mode": "window_access",
        "window_days": 7,
    },
    {
        "key": "group_challenge",
        "event_type": "group_challenge",
        "title": "Group Challenge",
        "description": "Small pod competition",
        "min_donation_cents": 1000,
        "unlock_mode": "window_access",
        "window_days": 7,
    },
    {
        "key": "charity_sprint",
        "event_type": "charity_sprint",
        "title": "Weekend Charity Sprint",
        "description": "Time-bound campaign event (2 days)",
        "min_donation_cents": 2000,
        "unlock_mode": "window_access",
        "window_days": 2,
    },
]


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def wallet_available_amount(wallet: Wallet) -> float:
    return float(wallet.available_balance or wallet.token_balance or 0.0)


def _naive_utc(dt: datetime | None) -> datetime | None:
    if dt is None:
        return None
    if dt.tzinfo is not None:
        return dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt


def _is_admin_role(role: str | None) -> bool:
    value = (role or "").strip().lower()
    return value in {"admin", "admine"}  # keep legacy compatibility


def _event_type_for_storage(event_type: str) -> str:
    return "group_challenge" if (event_type or "").strip().lower() == "solo" else event_type


def _is_solo_event_type(event_type: str | None, max_participants: int | None = None) -> bool:
    value = (event_type or "").strip().lower()
    return value == "solo" or (value != "one_on_one" and int(max_participants or 0) == 1)


def _effective_max_participants(event_type: str, max_participants: int | None) -> int | None:
    if _is_solo_event_type(event_type, max_participants):
        return 1
    return max_participants


def _event_public_type(
    event: TournamentEvent | None = None,
    *,
    event_type: str | None = None,
    max_participants: int | None = None,
) -> str:
    resolved_type = event.event_type if event is not None else event_type
    resolved_max = event.max_participants if event is not None else max_participants
    if _is_solo_event_type(resolved_type, resolved_max):
        return "solo"
    return (resolved_type or "group_challenge").strip().lower()


def _is_missing_relation_or_column_error(exc: Exception) -> bool:
    message = str(exc).lower()
    return (
        "undefinedtableerror" in message
        or "undefinedcolumnerror" in message
        or ("relation" in message and "does not exist" in message)
        or ("column" in message and "does not exist" in message)
    )


def _id_text_expr(column):
    return cast(column, String)


def _id_text_value(value: Any) -> str:
    return str(value)


def expected_holes(round_type: str) -> int:
    return 9 if round_type == "9hole" else 18


def to_float(value: Any, default: float = 0.0) -> float:
    if value is None:
        return default
    return float(value)


def clamp01_to_100(value: float) -> float:
    return max(0.0, min(100.0, value))


def normalize_inverse(value: float, best: float, worst: float) -> float:
    if worst <= best:
        return 50.0
    ratio = (value - best) / (worst - best)
    return clamp01_to_100((1.0 - ratio) * 100.0)


def normalize_direct(value: float, best: float, worst: float) -> float:
    if worst <= best:
        return 50.0
    ratio = (value - best) / (worst - best)
    return clamp01_to_100(ratio * 100.0)


def normalize_phone(phone_number: str) -> str:
    clean_phone = (phone_number or "").replace("+", "").strip()
    if clean_phone.startswith("0"):
        clean_phone = "254" + clean_phone[1:]
    if not clean_phone.startswith("254") or len(clean_phone) != 12 or not clean_phone.isdigit():
        raise HTTPException(status_code=400, detail="Phone number must be a valid Kenyan number")
    return clean_phone


def daraja_access_token() -> str:
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


def daraja_password() -> tuple[str, str]:
    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    data_to_encode = settings.DARAJA_SHORTCODE + settings.DARAJA_PASSKEY + timestamp
    password = base64.b64encode(data_to_encode.encode()).decode()
    return password, timestamp


async def create_audit(
    db: AsyncSession,
    round_id: str,
    actor_user_id: int,
    event_type: str,
    payload: dict[str, Any] | None = None,
) -> None:
    db.add(
        TournamentRoundAuditEvent(
            round_id=round_id,
            actor_user_id=actor_user_id,
            event_type=event_type,
            payload=payload or {},
        )
    )


async def get_round_for_user_or_admin(db: AsyncSession, round_id: str, user: User) -> TournamentRound:
    stmt = select(TournamentRound).where(TournamentRound.id == round_id)
    tournament_round = (await db.execute(stmt)).scalar_one_or_none()
    if not tournament_round:
        raise HTTPException(status_code=404, detail="Round not found")

    is_admin = _is_admin_role(user.role)
    if tournament_round.player_user_id != user.id and not is_admin:
        raise HTTPException(status_code=403, detail="Access denied")
    return tournament_round


async def load_round_holes(db: AsyncSession, round_id: str) -> list[TournamentRoundHole]:
    stmt = (
        select(TournamentRoundHole)
        .where(TournamentRoundHole.round_id == round_id)
        .order_by(TournamentRoundHole.hole_number.asc())
    )
    return list((await db.execute(stmt)).scalars().all())


async def compute_round_totals(db: AsyncSession, tournament_round: TournamentRound) -> dict[str, int]:
    holes = await load_round_holes(db, tournament_round.id)
    return {
        "holes_count": len(holes),
        "gross_score": sum(h.strokes for h in holes),
        "total_putts": sum(h.putts for h in holes),
        "gir_count": sum(1 for h in holes if h.gir),
        "fairways_hit_count": sum(1 for h in holes if h.fairway_hit is True),
        "penalties_total": sum(h.penalties for h in holes),
    }


async def upsert_trust_score(db: AsyncSession, user_id: int) -> float:
    profile_stmt = select(TournamentPlayerProfile).where(TournamentPlayerProfile.user_id == user_id)
    profile = (await db.execute(profile_stmt)).scalar_one_or_none()
    if not profile:
        profile = TournamentPlayerProfile(user_id=user_id, trust_score=Decimal("50.00"))
        db.add(profile)
        await db.flush()

    verified_rounds_stmt = select(func.count(TournamentRound.id)).where(
        TournamentRound.player_user_id == user_id,
        TournamentRound.status == "locked",
    )
    verified_rounds = int((await db.execute(verified_rounds_stmt)).scalar_one() or 0)

    open_flags_stmt = select(func.count(TournamentFraudFlag.id)).where(
        TournamentFraudFlag.user_id == user_id,
        TournamentFraudFlag.status == "open",
    )
    open_flags = int((await db.execute(open_flags_stmt)).scalar_one() or 0)

    score = 50 + min(40, verified_rounds * 3) - min(40, open_flags * 8)
    profile.trust_score = Decimal(str(clamp01_to_100(float(score))))
    return float(profile.trust_score)


async def flag_outlier_if_needed(db: AsyncSession, tournament_round: TournamentRound) -> None:
    if tournament_round.gross_score is None:
        return
    prior_stmt = (
        select(TournamentRound.gross_score)
        .where(
            TournamentRound.player_user_id == tournament_round.player_user_id,
            TournamentRound.status == "locked",
            TournamentRound.id != tournament_round.id,
            TournamentRound.gross_score.isnot(None),
        )
        .order_by(TournamentRound.played_at.desc())
        .limit(8)
    )
    prior_scores = [int(s) for s in (await db.execute(prior_stmt)).scalars().all()]
    if len(prior_scores) < 3:
        return

    baseline = sum(prior_scores) / len(prior_scores)
    if tournament_round.gross_score <= baseline - 15:
        db.add(
            TournamentFraudFlag(
                user_id=tournament_round.player_user_id,
                round_id=tournament_round.id,
                flag_type="sudden_drop",
                severity="medium",
                details={"baseline": round(baseline, 2), "score": tournament_round.gross_score},
            )
        )


class RoundCreateRequest(BaseModel):
    course_id: str
    played_at: datetime
    round_type: str = Field(pattern=r"^(9hole|18hole)$")
    marker_user_id: int | None = Field(default=None, ge=1)
    source: str = Field(default="manual", pattern=r"^(manual|live)$")


class RoundHoleUpsertRequest(BaseModel):
    par: int = Field(ge=3, le=6)
    strokes: int = Field(ge=1, le=15)
    putts: int = Field(ge=0, le=8)
    fairway_hit: bool | None = None
    gir: bool = False
    sand_save: bool = False
    penalties: int = Field(default=0, ge=0, le=6)


class RoundSubmitRequest(BaseModel):
    marker_user_id: int = Field(ge=1)


class RoundRejectRequest(BaseModel):
    reason: str = Field(min_length=3, max_length=300)


class RoundLockRequest(BaseModel):
    reason: str | None = Field(default=None, max_length=300)


class TeamDrawGenerateRequest(BaseModel):
    event_key: str = Field(min_length=2, max_length=80)
    team_size: int = Field(default=4, ge=2, le=8)
    user_ids: list[int]
    algorithm: str = Field(default="balanced_sum", pattern=r"^(balanced_sum|snake|tier|weighted_random)$")


class CourseCreateRequest(BaseModel):
    name: str = Field(min_length=2, max_length=200)
    location: str | None = Field(default=None, max_length=220)
    course_rating: Decimal = Field(ge=60, le=80)
    slope_rating: int = Field(ge=55, le=155)
    holes_count: int = Field(default=18, ge=9, le=18)
    default_par: int = Field(default=4, ge=3, le=6)


class EventCreateRequest(BaseModel):
    title: str = Field(min_length=3, max_length=180)
    event_type: str = Field(pattern=r"^(solo|one_on_one|skill_challenge|group_challenge|charity_sprint)$")
    description: str | None = Field(default=None, max_length=2000)
    min_donation_cents: int = Field(ge=100, le=100000)
    currency: str = Field(default="USD", max_length=8)
    unlock_mode: str = Field(default="single_use_ticket", pattern=r"^(single_use_ticket|window_access)$")
    start_at: datetime
    end_at: datetime
    max_participants: int | None = Field(default=None, ge=2, le=2000)


class EventDonateInitiateRequest(BaseModel):
    phone_number: str = Field(min_length=10, max_length=16)
    amount_cents: int = Field(ge=100, le=10000000)


class EventDonateConfirmRequest(BaseModel):
    checkout_request_id: str = Field(min_length=8, max_length=128)


class EventManualUnlockRequest(BaseModel):
    amount_cents: int = Field(ge=100, le=10000000)
    provider_ref: str = Field(min_length=4, max_length=128)


class EventWalletUnlockRequest(BaseModel):
    amount_cents: int = Field(ge=100, le=10000000)
    charity_id: str | None = Field(default=None, min_length=8, max_length=64)


class SessionCreateRequest(BaseModel):
    event_id: str
    scheduled_at: datetime
    invited_user_ids: list[int] = Field(default_factory=list)


class InviteActionRequest(BaseModel):
    action: str = Field(pattern=r"^(accept|decline)$")


class FriendRequestCreateRequest(BaseModel):
    receiver_user_id: int = Field(ge=1)


class FriendRequestActionRequest(BaseModel):
    action: str = Field(pattern=r"^(accept|decline)$")


class SessionScoreSubmitRequest(BaseModel):
    total_score: int = Field(ge=1, le=200)
    holes_played: int | None = Field(default=None, ge=9, le=18)
    hole_scores: list[int] = Field(default_factory=list)
    total_putts: int | None = Field(default=None, ge=0, le=120)
    gir_count: int | None = Field(default=None, ge=0, le=18)
    fairways_hit_count: int | None = Field(default=None, ge=0, le=18)
    penalties_total: int | None = Field(default=None, ge=0, le=30)
    notes: str | None = Field(default=None, max_length=1000)
    marker_user_id: int | None = Field(default=None, ge=1)


class SessionScoreReviewRequest(BaseModel):
    reason: str | None = Field(default=None, max_length=300)


def _balanced_sum_teams(players: list[dict[str, Any]], team_size: int) -> list[list[dict[str, Any]]]:
    players_sorted = sorted(players, key=lambda x: x["rating"], reverse=True)
    team_count = max(1, math.ceil(len(players_sorted) / team_size))
    teams: list[list[dict[str, Any]]] = [[] for _ in range(team_count)]
    totals = [0.0 for _ in range(team_count)]

    for player in players_sorted:
        candidate_idx = None
        candidate_total = None
        for idx in range(team_count):
            if len(teams[idx]) >= team_size:
                continue
            if candidate_idx is None or totals[idx] < candidate_total:
                candidate_idx = idx
                candidate_total = totals[idx]
        if candidate_idx is None:
            candidate_idx = min(range(team_count), key=lambda i: totals[i])
        teams[candidate_idx].append(player)
        totals[candidate_idx] += player["rating"]
    return teams


async def _active_unlock_for_user_event(
    db: AsyncSession,
    user_id: int,
    event_id: str,
) -> TournamentEventUnlock | None:
    now = utcnow()
    stmt = (
        select(TournamentEventUnlock)
        .where(
            TournamentEventUnlock.user_id == user_id,
            _id_text_expr(TournamentEventUnlock.event_id) == _id_text_value(event_id),
            TournamentEventUnlock.status == "active",
            or_(TournamentEventUnlock.expires_at.is_(None), TournamentEventUnlock.expires_at > now),
        )
        .order_by(TournamentEventUnlock.unlocked_at.desc())
        .limit(1)
    )
    return (await db.execute(stmt)).scalar_one_or_none()


async def _best_unlock_for_user_event(
    db: AsyncSession,
    user_id: int,
    event: TournamentEvent,
) -> TournamentEventUnlock | None:
    unlock = await _active_unlock_for_user_event(db, user_id, event.id)
    if unlock:
        return unlock

    # Guardrail: preserve paid access for window-based events for their active window,
    # even if a previous build marked unlock rows as consumed.
    if event.unlock_mode == "window_access":
        now = utcnow()
        if event.status != "active" or now < event.start_at or now > event.end_at:
            return None
        legacy_stmt = (
            select(TournamentEventUnlock)
            .where(
                TournamentEventUnlock.user_id == user_id,
                _id_text_expr(TournamentEventUnlock.event_id) == _id_text_value(event.id),
                TournamentEventUnlock.unlock_mode == "window_access",
            )
            .order_by(TournamentEventUnlock.unlocked_at.desc())
            .limit(1)
        )
        legacy_unlock = (await db.execute(legacy_stmt)).scalar_one_or_none()
        if legacy_unlock:
            if legacy_unlock.status != "active":
                legacy_unlock.status = "active"
                legacy_unlock.expires_at = event.end_at
                await db.commit()
                await db.refresh(legacy_unlock)
            return legacy_unlock
    return None


async def auto_close_overdue_sessions(db: AsyncSession) -> None:
    now = utcnow()
    overdue_stmt = (
        select(TournamentChallengeSession)
        .where(
            TournamentChallengeSession.status == "in_progress",
            TournamentChallengeSession.auto_close_at.isnot(None),
            TournamentChallengeSession.auto_close_at <= now,
        )
    )
    try:
        overdue_sessions = (await db.execute(overdue_stmt)).scalars().all()
    except ProgrammingError as exc:
        if not _is_missing_relation_or_column_error(exc):
            raise
        await db.rollback()
        return
    if not overdue_sessions:
        return

    for session in overdue_sessions:
        session.status = "auto_closed"
        session.completed_at = session.completed_at or now
        db.add(
            TournamentInboxMessage(
                recipient_user_id=session.creator_user_id,
                sender_user_id=session.creator_user_id,
                session_id=session.id,
                message_type="system",
                title="Session Auto Closed",
                body="This challenge was auto-closed after 48 hours without ending.",
                status="unread",
            )
        )
        participants = (
            await db.execute(
                select(TournamentChallengeParticipant).where(
                    _id_text_expr(TournamentChallengeParticipant.session_id) == _id_text_value(session.id),
                    TournamentChallengeParticipant.user_id != session.creator_user_id,
                    TournamentChallengeParticipant.invite_state == "accepted",
                )
            )
        ).scalars().all()
        for p in participants:
            db.add(
                TournamentInboxMessage(
                    recipient_user_id=p.user_id,
                    sender_user_id=session.creator_user_id,
                    session_id=session.id,
                    message_type="system",
                    title="Session Auto Closed",
                    body="This challenge was auto-closed after 48 hours without ending.",
                    status="unread",
                )
            )
    await db.commit()


async def reconcile_session_invite_status(db: AsyncSession, session: TournamentChallengeSession) -> bool:
    participants = (
        await db.execute(
            select(TournamentChallengeParticipant.invite_state).where(
                _id_text_expr(TournamentChallengeParticipant.session_id) == _id_text_value(session.id)
            )
        )
    ).scalars().all()
    if not participants:
        return False

    pending_count = sum(1 for s in participants if s == "pending")
    declined_count = sum(1 for s in participants if s == "declined")
    changed = False

    if session.status in {"completed", "auto_closed", "cancelled"}:
        return False

    if declined_count > 0:
        if session.status != "cancelled":
            session.status = "cancelled"
            changed = True
        return changed

    if pending_count == 0:
        if session.status == "pending_invites":
            session.status = "ready_to_start"
            changed = True
    else:
        if session.status == "ready_to_start":
            session.status = "pending_invites"
            changed = True
    return changed


async def ensure_default_events(db: AsyncSession) -> None:
    now = utcnow()
    changed = False
    for cfg in DEFAULT_EVENT_CONFIGS:
        existing_stmt = (
            select(TournamentEvent)
            .where(TournamentEvent.title == cfg["title"], TournamentEvent.status != "cancelled")
            .order_by(TournamentEvent.created_at.desc())
            .limit(1)
        )
        existing = (await db.execute(existing_stmt)).scalar_one_or_none()
        if existing:
            cfg_stored_type = cfg.get("stored_event_type", cfg["event_type"])
            if existing.event_type != cfg_stored_type:
                existing.event_type = cfg_stored_type
                changed = True
            if existing.unlock_mode != cfg["unlock_mode"]:
                existing.unlock_mode = cfg["unlock_mode"]
                changed = True
            cfg_max_participants = cfg.get("max_participants")
            if existing.max_participants != cfg_max_participants:
                existing.max_participants = cfg_max_participants
                changed = True
            # Keep lifecycle truthful: ended/closed events must not be auto-reactivated.
            # This prevents old events from reappearing as active and requiring re-unlock.
            if existing.status == "active" and existing.end_at < now:
                existing.status = "closed"
                changed = True
            continue

        event = TournamentEvent(
            title=cfg["title"],
            event_type=cfg.get("stored_event_type", cfg["event_type"]),
            description=cfg["description"],
            min_donation_cents=int(cfg["min_donation_cents"]),
            currency="USD",
            unlock_mode=cfg["unlock_mode"],
            start_at=now,
            end_at=now + timedelta(days=int(cfg["window_days"])),
            status="active",
            max_participants=cfg.get("max_participants"),
            created_by=0,
        )
        db.add(event)
        changed = True
    if changed:
        await db.commit()


@router.post("/admin/events", status_code=status.HTTP_201_CREATED)
async def admin_create_event(
    payload: EventCreateRequest,
    current_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    if payload.end_at <= payload.start_at:
        raise HTTPException(status_code=400, detail="end_at must be after start_at")

    stored_event_type = _event_type_for_storage(payload.event_type)
    max_participants = _effective_max_participants(payload.event_type, payload.max_participants)
    event = TournamentEvent(
        title=payload.title.strip(),
        event_type=stored_event_type,
        description=(payload.description or "").strip() or None,
        min_donation_cents=payload.min_donation_cents,
        currency=payload.currency.upper(),
        unlock_mode=payload.unlock_mode,
        start_at=payload.start_at,
        end_at=payload.end_at,
        status="active",
        max_participants=max_participants,
        created_by=current_user.id,
    )
    db.add(event)
    await db.commit()
    await db.refresh(event)

    return {
        "id": event.id,
        "title": event.title,
        "event_type": _event_public_type(event),
        "min_donation_cents": event.min_donation_cents,
        "unlock_mode": event.unlock_mode,
        "status": event.status,
        "payment_optional": True,
    }


@router.get("/events")
async def list_events(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    await ensure_default_events(db)
    now = utcnow()
    stmt = (
        select(TournamentEvent)
        .where(TournamentEvent.status == "active", TournamentEvent.end_at >= now)
        .order_by(TournamentEvent.start_at.asc())
    )
    events = (await db.execute(stmt)).scalars().all()
    out: list[dict[str, Any]] = []
    for event in events:
        out.append(
            {
                "id": event.id,
                "title": event.title,
                "event_type": _event_public_type(event),
                "description": event.description,
                "min_donation_cents": event.min_donation_cents,
                "currency": event.currency,
                "unlock_mode": event.unlock_mode,
                "start_at": event.start_at,
                "end_at": event.end_at,
                "is_unlocked": True,
                "tickets_left": None,
                "payment_optional": True,
            }
        )
    return {"events": out}


@router.get("/public/events")
async def public_events(
    current_user: User | None = Depends(get_current_user_optional),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    try:
        await ensure_default_events(db)
        now = utcnow()
        stmt = (
            select(TournamentEvent)
            .where(TournamentEvent.status == "active", TournamentEvent.end_at >= now)
            .order_by(TournamentEvent.start_at.asc())
        )
        events = (await db.execute(stmt)).scalars().all()
        out: list[dict[str, Any]] = []
        for event in events:
            out.append(
                {
                    "id": event.id,
                    "title": event.title,
                    "event_type": _event_public_type(event),
                    "description": event.description,
                    "min_donation_cents": event.min_donation_cents,
                    "currency": event.currency,
                    "unlock_mode": event.unlock_mode,
                    "start_at": event.start_at,
                    "end_at": event.end_at,
                    "is_unlocked": True,
                    "tickets_left": None,
                    "payment_optional": True,
                    "read_only": current_user is None,
                }
            )
        return {"events": out}
    except Exception:
        now = utcnow()
        fallback_events: list[dict[str, Any]] = []
        for cfg in DEFAULT_EVENT_CONFIGS:
            fallback_events.append(
                {
                    "id": cfg.get("key", cfg["event_type"]),
                    "title": cfg["title"],
                    "event_type": cfg["event_type"],
                    "description": cfg["description"],
                    "min_donation_cents": int(cfg["min_donation_cents"]),
                    "currency": "USD",
                    "unlock_mode": cfg["unlock_mode"],
                    "start_at": now,
                    "end_at": now + timedelta(days=int(cfg["window_days"])),
                    "is_unlocked": True,
                    "tickets_left": None,
                    "payment_optional": True,
                    "read_only": current_user is None,
                }
            )
        return {"events": fallback_events, "fallback": True}


@router.get("/events/{event_id}/my-access")
async def my_event_access(
    event_id: str,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    await ensure_default_events(db)
    event = (
        await db.execute(
            select(TournamentEvent).where(_id_text_expr(TournamentEvent.id) == _id_text_value(event_id))
        )
    ).scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")
    unlock = await _best_unlock_for_user_event(db, current_user.id, event)
    return {
        "event_id": event_id,
        "unlocked": True,
        "unlock_id": unlock.id if unlock else None,
        "unlock_mode": unlock.unlock_mode if unlock else event.unlock_mode,
        "tickets_left": None,
        "expires_at": unlock.expires_at if unlock else None,
        "status": unlock.status if unlock else "available",
        "payment_optional": True,
        "min_donation_cents": event.min_donation_cents,
        "currency": event.currency,
    }


@router.post("/events/{event_id}/donate/initiate")
async def initiate_event_donation(
    event_id: str,
    payload: EventDonateInitiateRequest,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    await ensure_default_events(db)
    now = utcnow()
    event = (
        await db.execute(
            select(TournamentEvent).where(_id_text_expr(TournamentEvent.id) == _id_text_value(event_id))
        )
    ).scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")
    if event.status != "active" or now < event.start_at or now > event.end_at:
        raise HTTPException(status_code=409, detail="Event is not currently open")
    if payload.amount_cents < int(event.min_donation_cents):
        raise HTTPException(
            status_code=400,
            detail=f"Minimum donation is {event.min_donation_cents} cents",
        )

    phone = normalize_phone(payload.phone_number)
    amount_kes = max(1, math.ceil(payload.amount_cents / 100))

    token = daraja_access_token()
    password, timestamp = daraja_password()
    stk_url = f"{settings.daraja_base_url}/mpesa/stkpush/v1/processrequest"
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    request_payload = {
        "BusinessShortCode": settings.DARAJA_SHORTCODE,
        "Password": password,
        "Timestamp": timestamp,
        "TransactionType": "CustomerPayBillOnline",
        "Amount": amount_kes,
        "PartyA": phone,
        "PartyB": settings.DARAJA_SHORTCODE,
        "PhoneNumber": phone,
        "CallBackURL": settings.DARAJA_CALLBACK_URL,
        "AccountReference": f"event{event.id[:8]}",
        "TransactionDesc": f"Event donation {event.title[:40]}",
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
        amount=float(amount_kes),
        checkout_request_id=checkout_request_id,
        statuz="PENDING",
        purpose="EVENT_DONATION",
        purpose_ref=event.id,
        metadata_json={
            "source": "tournament_event_donation",
            "event_id": event.id,
            "event_title": event.title,
            "phone": phone,
            "requested_amount_cents": payload.amount_cents,
            "currency": event.currency,
        },
    )
    db.add(tx)
    await db.flush()

    donation = TournamentEventDonation(
        user_id=current_user.id,
        event_id=event.id,
        amount_cents=payload.amount_cents,
        currency=event.currency,
        provider="mpesa",
        provider_ref=checkout_request_id,
        transaction_id=tx.id,
        status="pending",
    )
    db.add(donation)
    await db.commit()

    return {
        "checkout_request_id": checkout_request_id,
        "event_id": event.id,
        "event_title": event.title,
        "amount_cents": payload.amount_cents,
        "status": "pending",
        "customer_message": response_json.get("CustomerMessage", "STK push sent"),
    }


@router.post("/events/{event_id}/donate/confirm")
async def confirm_event_donation(
    event_id: str,
    payload: EventDonateConfirmRequest,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    await ensure_default_events(db)
    event = (
        await db.execute(
            select(TournamentEvent).where(_id_text_expr(TournamentEvent.id) == _id_text_value(event_id))
        )
    ).scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    donation_stmt = select(TournamentEventDonation).where(
        TournamentEventDonation.provider_ref == payload.checkout_request_id,
        _id_text_expr(TournamentEventDonation.event_id) == _id_text_value(event_id),
        TournamentEventDonation.user_id == current_user.id,
    )
    donation = (await db.execute(donation_stmt)).scalar_one_or_none()
    if not donation:
        raise HTTPException(status_code=404, detail="Donation request not found")

    tx_stmt = select(Transaction).where(
        Transaction.checkout_request_id == payload.checkout_request_id,
        Transaction.user_id == current_user.id,
    )
    tx = (await db.execute(tx_stmt)).scalar_one_or_none()
    if not tx:
        raise HTTPException(status_code=404, detail="Payment transaction not found")

    tx_status = (tx.statuz or "").upper()
    if tx_status == "PENDING":
        return {"status": "pending", "message": "Payment not yet confirmed by M-Pesa"}
    if tx_status != "SUCCESS":
        donation.status = "failed"
        await db.commit()
        return {"status": "failed", "message": "Payment failed"}

    if donation.amount_cents < int(event.min_donation_cents):
        donation.status = "completed"
        donation.completed_at = utcnow()
        await db.commit()
        return {
            "status": "insufficient",
            "message": "Donation completed but below event minimum amount",
            "required_cents": int(event.min_donation_cents),
            "paid_cents": int(donation.amount_cents),
        }

    donation.status = "completed"
    donation.completed_at = utcnow()

    existing_unlock = await _best_unlock_for_user_event(db, current_user.id, event)
    if existing_unlock and existing_unlock.status == "active":
        await db.commit()
        tickets_left_existing = int(existing_unlock.ticket_count) - int(existing_unlock.tickets_used)
        return {
            "status": "donation_recorded",
            "event_id": event.id,
            "unlock_id": existing_unlock.id,
            "unlock_mode": existing_unlock.unlock_mode,
            "tickets_left": tickets_left_existing,
            "expires_at": existing_unlock.expires_at,
        }

    unlock_stmt = select(TournamentEventUnlock).where(TournamentEventUnlock.donation_id == donation.id)
    unlock = (await db.execute(unlock_stmt)).scalar_one_or_none()
    if not unlock:
        expires_at = event.end_at if event.unlock_mode == "window_access" else None
        unlock = TournamentEventUnlock(
            user_id=current_user.id,
            event_id=event.id,
            donation_id=donation.id,
            unlock_mode=event.unlock_mode,
            ticket_count=1,
            tickets_used=0,
            expires_at=expires_at,
            status="active",
        )
        db.add(unlock)

    await db.commit()
    await db.refresh(unlock)

    tickets_left = int(unlock.ticket_count) - int(unlock.tickets_used)
    return {
        "status": "donated",
        "event_id": event.id,
        "unlock_id": unlock.id,
        "unlock_mode": unlock.unlock_mode,
        "tickets_left": tickets_left,
        "expires_at": unlock.expires_at,
    }


@router.post("/events/{event_id}/join")
async def join_event(
    event_id: str,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    await ensure_default_events(db)
    now = utcnow()
    event = (
        await db.execute(
            select(TournamentEvent).where(_id_text_expr(TournamentEvent.id) == _id_text_value(event_id))
        )
    ).scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")
    if event.status != "active" or now < event.start_at or now > event.end_at:
        raise HTTPException(status_code=409, detail="Event is not joinable right now")

    unlock = await _best_unlock_for_user_event(db, current_user.id, event)
    if not unlock:
        raise HTTPException(status_code=403, detail="Event participation is unavailable right now.")

    already_joined_stmt = select(TournamentEventParticipant).where(
        TournamentEventParticipant.event_id == event_id,
        TournamentEventParticipant.user_id == current_user.id,
    )
    already_joined = (await db.execute(already_joined_stmt)).scalar_one_or_none()
    if already_joined:
        return {"joined": True, "event_id": event_id, "participant_id": already_joined.id}

    if event.max_participants:
        count_stmt = select(func.count(TournamentEventParticipant.id)).where(TournamentEventParticipant.event_id == event_id)
        count = int((await db.execute(count_stmt)).scalar_one() or 0)
        if count >= int(event.max_participants):
            raise HTTPException(status_code=409, detail="Event is full")

    if unlock.unlock_mode == "single_use_ticket":
        if int(unlock.tickets_used) >= int(unlock.ticket_count):
            unlock.status = "consumed"
            await db.commit()
            raise HTTPException(status_code=409, detail="No tickets left for this event")
        unlock.tickets_used = int(unlock.tickets_used) + 1
        if int(unlock.tickets_used) >= int(unlock.ticket_count):
            unlock.status = "consumed"

    participant = TournamentEventParticipant(
        event_id=event_id,
        user_id=current_user.id,
        unlock_id=unlock.id,
        state="joined",
    )
    db.add(participant)
    await db.commit()
    await db.refresh(participant)
    return {"joined": True, "event_id": event_id, "participant_id": participant.id}


@router.post("/events/{event_id}/unlock/manual")
async def manual_unlock_event(
    event_id: str,
    payload: EventManualUnlockRequest,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    if (settings.ENVIRONMENT or "").strip().lower() not in {"development", "dev", "local", "test"}:
        raise HTTPException(
            status_code=403,
            detail="Manual unlock is disabled outside development environments",
        )

    await ensure_default_events(db)
    event = (
        await db.execute(
            select(TournamentEvent).where(_id_text_expr(TournamentEvent.id) == _id_text_value(event_id))
        )
    ).scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")
    if payload.amount_cents < int(event.min_donation_cents):
        raise HTTPException(
            status_code=400,
            detail=f"Minimum donation is {event.min_donation_cents} cents",
        )

    existing_unlock = await _best_unlock_for_user_event(db, current_user.id, event)
    if existing_unlock and existing_unlock.status == "active":
        tickets_left_existing = int(existing_unlock.ticket_count) - int(existing_unlock.tickets_used)
        return {
            "status": "donation_recorded",
            "event_id": event.id,
            "unlock_id": existing_unlock.id,
            "unlock_mode": existing_unlock.unlock_mode,
            "tickets_left": tickets_left_existing,
            "expires_at": existing_unlock.expires_at,
        }

    existing = (
        await db.execute(
            select(TournamentEventDonation).where(
                TournamentEventDonation.provider_ref == payload.provider_ref,
                TournamentEventDonation.user_id == current_user.id,
            )
        )
    ).scalar_one_or_none()
    if existing:
        raise HTTPException(status_code=409, detail="provider_ref already used")

    donation = TournamentEventDonation(
        user_id=current_user.id,
        event_id=event.id,
        amount_cents=payload.amount_cents,
        currency=event.currency,
        provider="stripe",
        provider_ref=payload.provider_ref,
        status="completed",
        completed_at=utcnow(),
    )
    db.add(donation)
    await db.flush()

    unlock = TournamentEventUnlock(
        user_id=current_user.id,
        event_id=event.id,
        donation_id=donation.id,
        unlock_mode=event.unlock_mode,
        ticket_count=1,
        tickets_used=0,
        expires_at=event.end_at if event.unlock_mode == "window_access" else None,
        status="active",
    )
    db.add(unlock)
    await db.commit()
    await db.refresh(unlock)

    return {
        "status": "donated",
        "simulation": True,
        "event_id": event.id,
        "unlock_id": unlock.id,
        "unlock_mode": unlock.unlock_mode,
    }


@router.post("/events/{event_id}/unlock/wallet")
async def wallet_unlock_event(
    event_id: str,
    payload: EventWalletUnlockRequest,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    await ensure_default_events(db)
    now = utcnow()
    event = (
        await db.execute(
            select(TournamentEvent).where(_id_text_expr(TournamentEvent.id) == _id_text_value(event_id))
        )
    ).scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")
    if event.status != "active" or now < event.start_at or now > event.end_at:
        raise HTTPException(status_code=409, detail="Event is not currently open")
    if payload.amount_cents < int(event.min_donation_cents):
        raise HTTPException(
            status_code=400,
            detail=f"Minimum donation is {event.min_donation_cents} cents",
        )

    setting = (
        await db.execute(
            select(GolfUserCharitySetting).where(GolfUserCharitySetting.user_id == current_user.id)
        )
    ).scalar_one_or_none()
    selected_charity_id = (payload.charity_id or "").strip() or (setting.charity_id if setting else None)
    if not selected_charity_id:
        raise HTTPException(status_code=400, detail="Select a charity before making an event donation.")
    charity = (
        await db.execute(
            select(GolfCharity).where(
                GolfCharity.id == selected_charity_id,
                GolfCharity.is_active.is_(True),
            )
        )
    ).scalar_one_or_none()
    if not charity:
        raise HTTPException(status_code=404, detail="Selected charity is not active or does not exist.")

    existing_unlock = await _best_unlock_for_user_event(db, current_user.id, event)
    if existing_unlock and existing_unlock.status == "active":
        tickets_left_existing = int(existing_unlock.ticket_count) - int(existing_unlock.tickets_used)
        return {
            "status": "donation_recorded",
            "event_id": event.id,
            "unlock_id": existing_unlock.id,
            "unlock_mode": existing_unlock.unlock_mode,
            "tickets_left": tickets_left_existing,
            "expires_at": existing_unlock.expires_at,
        }

    wallet = (
        await db.execute(select(Wallet).where(Wallet.user_id == current_user.id).limit(1))
    ).scalar_one_or_none()
    if not wallet:
        wallet = Wallet(
            user_id=current_user.id,
            available_balance=0.0,
            total_topups=0.0,
            total_donated=0.0,
            token_balance=0.0,
            total_purchased=0.0,
        )
        db.add(wallet)
        await db.flush()

    amount_usd = payload.amount_cents / 100.0
    available = wallet_available_amount(wallet)
    if available < amount_usd:
        raise HTTPException(
            status_code=409,
            detail=f"Insufficient wallet balance. Available ${available:.2f}, required ${amount_usd:.2f}",
        )

    wallet.available_balance = available - amount_usd
    wallet.total_donated = float(wallet.total_donated or 0.0) + amount_usd
    wallet.token_balance = float(wallet.available_balance or 0.0)
    wallet.last_updated = now

    ledger = WalletLedger(
        user_id=current_user.id,
        entry_type="event_donation",
        amount=-amount_usd,
        currency="USD",
        reference_type="tournament_event",
        reference_id=event.id,
        status="completed",
        metadata_json={
            "event_id": event.id,
            "event_type": event.event_type,
            "charity_id": charity.id,
        },
    )
    db.add(ledger)
    await db.flush()

    donation = TournamentEventDonation(
        user_id=current_user.id,
        event_id=event.id,
        amount_cents=payload.amount_cents,
        currency=event.currency,
        provider="wallet",
        provider_ref=f"wallet_{ledger.id}_{uuid.uuid4().hex[:8]}",
        status="completed",
        completed_at=now,
    )
    db.add(donation)
    await db.flush()

    # Persist the selected charity as the user's active charity preference.
    if setting:
        setting.charity_id = charity.id
    else:
        db.add(
            GolfUserCharitySetting(
                user_id=current_user.id,
                charity_id=charity.id,
                contribution_pct=Decimal("15.00"),
            )
        )

    # Credit selected charity account and donation ledger.
    charity.total_raised_cents = int(charity.total_raised_cents or 0) + int(payload.amount_cents)
    db.add(
        GolfCharityDonation(
            user_id=current_user.id,
            charity_id=charity.id,
            amount_cents=payload.amount_cents,
            currency=event.currency,
            payment_provider="wallet",
            payment_reference=donation.provider_ref,
        )
    )

    unlock = TournamentEventUnlock(
        user_id=current_user.id,
        event_id=event.id,
        donation_id=donation.id,
        unlock_mode=event.unlock_mode,
        ticket_count=1,
        tickets_used=0,
        expires_at=event.end_at if event.unlock_mode == "window_access" else None,
        status="active",
    )
    db.add(unlock)
    await db.commit()
    await db.refresh(unlock)

    return {
        "status": "donated",
        "event_id": event.id,
        "unlock_id": unlock.id,
        "unlock_mode": unlock.unlock_mode,
        "wallet_available_amount": float(wallet.available_balance or 0.0),
        "charity_id": charity.id,
        "charity_name": charity.name,
    }


@router.get("/players/available")
async def list_available_players(
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = (
        select(User)
        .where(
            User.id != current_user.id,
            User.role.in_(["subscriber", "admin", "admine"]),
        )
        .order_by(User.last_login.desc().nullslast(), User.id.asc())
        .limit(100)
    )
    users = (await db.execute(stmt)).scalars().all()
    user_ids = [u.id for u in users]
    pair_stmt = select(TournamentFriendRequest).where(
        or_(
            and_(
                TournamentFriendRequest.sender_user_id == current_user.id,
                TournamentFriendRequest.receiver_user_id.in_(user_ids),
            ),
            and_(
                TournamentFriendRequest.receiver_user_id == current_user.id,
                TournamentFriendRequest.sender_user_id.in_(user_ids),
            ),
        )
    )
    requests = (await db.execute(pair_stmt)).scalars().all() if user_ids else []
    status_map: dict[int, dict[str, Any]] = {}
    for fr in requests:
        other_id = (
            fr.receiver_user_id
            if fr.sender_user_id == current_user.id
            else fr.sender_user_id
        )
        current = status_map.get(other_id)
        # Prefer friend/accepted status over pending/declined.
        if current and current.get("friend_status") == "friend":
            continue
        if fr.status == "accepted":
            status_map[other_id] = {
                "friend_status": "friend",
                "friend_request_id": fr.id,
            }
        elif fr.status == "pending":
            status_map[other_id] = {
                "friend_status": "outgoing_pending"
                if fr.sender_user_id == current_user.id
                else "incoming_pending",
                "friend_request_id": fr.id,
            }
        else:
            status_map.setdefault(
                other_id,
                {"friend_status": "none", "friend_request_id": fr.id},
            )
    now = _naive_utc(utcnow()) or datetime.utcnow()
    out = []
    for u in users:
        last_login = _naive_utc(u.last_login)
        online = False
        if last_login:
            online = (now - last_login).total_seconds() <= 600
        out.append(
            {
                "id": u.id,
                "username": u.username,
                "email": u.email,
                "club_affiliation": u.club_affiliation,
                "profile_pic": u.profile_pic,
                "status": u.status,
                "is_online": online,
                "last_login": u.last_login,
                "friend_status": status_map.get(u.id, {}).get("friend_status", "none"),
                "friend_request_id": status_map.get(u.id, {}).get("friend_request_id"),
            }
        )
    return {"players": out}


@router.post("/friends/requests", status_code=status.HTTP_201_CREATED)
async def send_friend_request(
    payload: FriendRequestCreateRequest,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    if payload.receiver_user_id == current_user.id:
        raise HTTPException(status_code=400, detail="You cannot send a friend request to yourself.")

    receiver = (
        await db.execute(
            select(User).where(
                User.id == payload.receiver_user_id,
                User.role.in_(["subscriber", "admin", "admine"]),
            )
        )
    ).scalar_one_or_none()
    if not receiver:
        raise HTTPException(status_code=404, detail="Player not found.")

    existing_stmt = select(TournamentFriendRequest).where(
        or_(
            and_(
                TournamentFriendRequest.sender_user_id == current_user.id,
                TournamentFriendRequest.receiver_user_id == payload.receiver_user_id,
            ),
            and_(
                TournamentFriendRequest.sender_user_id == payload.receiver_user_id,
                TournamentFriendRequest.receiver_user_id == current_user.id,
            ),
        )
    ).order_by(TournamentFriendRequest.created_at.desc())
    existing = (await db.execute(existing_stmt)).scalars().all()
    for fr in existing:
        if fr.status == "accepted":
            raise HTTPException(status_code=409, detail="You are already friends.")
        if fr.status == "pending":
            if fr.sender_user_id == current_user.id:
                raise HTTPException(status_code=409, detail="Friend request already sent.")
            raise HTTPException(status_code=409, detail="This user has already sent you a request. Check inbox.")

    fr = TournamentFriendRequest(
        sender_user_id=current_user.id,
        receiver_user_id=payload.receiver_user_id,
        status="pending",
    )
    db.add(fr)
    await db.commit()
    await db.refresh(fr)

    return {
        "id": fr.id,
        "sender_user_id": fr.sender_user_id,
        "receiver_user_id": fr.receiver_user_id,
        "status": fr.status,
        "created_at": fr.created_at,
    }


@router.get("/friends/requests/incoming")
async def incoming_friend_requests(
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = (
        select(TournamentFriendRequest, User)
        .join(User, User.id == TournamentFriendRequest.sender_user_id)
        .where(
            TournamentFriendRequest.receiver_user_id == current_user.id,
            TournamentFriendRequest.status == "pending",
        )
        .order_by(TournamentFriendRequest.created_at.desc())
    )
    rows = (await db.execute(stmt)).all()
    return {
        "requests": [
            {
                "id": fr.id,
                "sender_user_id": fr.sender_user_id,
                "sender_username": sender.username,
                "sender_email": sender.email,
                "status": fr.status,
                "created_at": fr.created_at,
            }
            for fr, sender in rows
        ]
    }


@router.post("/friends/requests/{request_id}/action")
async def action_friend_request(
    request_id: str,
    payload: FriendRequestActionRequest,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = select(TournamentFriendRequest).where(
        TournamentFriendRequest.id == request_id,
        TournamentFriendRequest.receiver_user_id == current_user.id,
    )
    fr = (await db.execute(stmt)).scalar_one_or_none()
    if not fr:
        raise HTTPException(status_code=404, detail="Friend request not found.")
    if fr.status != "pending":
        raise HTTPException(status_code=409, detail="Friend request already actioned.")

    fr.status = "accepted" if payload.action == "accept" else "declined"
    fr.responded_at = utcnow()
    await db.commit()

    return {"ok": True, "request_id": fr.id, "action": payload.action, "status": fr.status}


@router.post("/sessions", status_code=status.HTTP_201_CREATED)
async def create_challenge_session(
    payload: SessionCreateRequest,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    await ensure_default_events(db)
    event = (
        await db.execute(
            select(TournamentEvent).where(_id_text_expr(TournamentEvent.id) == _id_text_value(payload.event_id))
        )
    ).scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")
    if event.status != "active":
        raise HTTPException(status_code=409, detail="Event is not active")

    invitees = sorted(set([uid for uid in payload.invited_user_ids if uid != current_user.id]))
    is_solo_event = _is_solo_event_type(event.event_type, event.max_participants)
    if event.event_type == "one_on_one" and len(invitees) != 1:
        raise HTTPException(status_code=400, detail="1v1 Duel requires exactly one invited player")
    if is_solo_event and invitees:
        raise HTTPException(status_code=400, detail="Solo event does not require invited players")

    # Legacy compatibility: older data can still expose `solo`, while sessions
    # are stored with `group_challenge` + max_participants=1.
    stored_event_type = _event_type_for_storage(event.event_type)
    session = TournamentChallengeSession(
        event_id=event.id,
        event_type=stored_event_type,
        creator_user_id=current_user.id,
        scheduled_at=payload.scheduled_at,
        status="pending_invites" if invitees else "ready_to_start",
    )
    db.add(session)
    await db.flush()

    db.add(
        TournamentChallengeParticipant(
            session_id=session.id,
            user_id=current_user.id,
            role="player",
            invite_state="accepted",
            joined_at=utcnow(),
        )
    )

    for invited_user_id in invitees:
        db.add(
            TournamentChallengeParticipant(
                session_id=session.id,
                user_id=invited_user_id,
                role="player",
                invite_state="pending",
            )
        )
        msg = TournamentInboxMessage(
            recipient_user_id=invited_user_id,
            sender_user_id=current_user.id,
            session_id=session.id,
            message_type="invite",
            title=f"Challenge Invite: {event.title}",
            body=(
                f"{current_user.username} invited you to {event.title} on "
                f"{payload.scheduled_at.isoformat()}. Accept to join."
            ),
            status="unread",
        )
        db.add(msg)

    try:
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        message = str(exc).lower()
        if "ck_tournament_challenge_session_type" in message:
            raise HTTPException(
                status_code=409,
                detail="Selected challenge type is not supported in the current schema.",
            ) from exc
        raise HTTPException(
            status_code=409,
            detail="Could not create challenge session due to a data conflict.",
        ) from exc
    except ProgrammingError as exc:
        await db.rollback()
        if _is_missing_relation_or_column_error(exc):
            raise HTTPException(
                status_code=503,
                detail="Tournament schema is not fully migrated. Apply latest SQL patches and retry.",
            ) from exc
        raise

    return {
        "session_id": session.id,
        "event_id": session.event_id,
        "event_type": _event_public_type(event),
        "status": session.status,
        "scheduled_at": session.scheduled_at,
        "invited_count": len(invitees),
    }


@router.get("/sessions/mine")
async def list_my_sessions(
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    await auto_close_overdue_sessions(db)
    participant_stmt = select(TournamentChallengeParticipant.session_id).where(
        TournamentChallengeParticipant.user_id == current_user.id
    )
    session_ids = [sid for sid in (await db.execute(participant_stmt)).scalars().all()]
    if not session_ids:
        return {"sessions": []}

    try:
        sessions = (
            await db.execute(
                select(TournamentChallengeSession)
                .where(_id_text_expr(TournamentChallengeSession.id).in_([_id_text_value(sid) for sid in session_ids]))
                .order_by(TournamentChallengeSession.scheduled_at.desc())
            )
        ).scalars().all()
    except ProgrammingError as exc:
        if not _is_missing_relation_or_column_error(exc):
            raise
        await db.rollback()
        return {"sessions": []}
    event_map: dict[str, TournamentEvent] = {}
    event_ids = sorted({_id_text_value(s.event_id) for s in sessions})
    if event_ids:
        event_rows = (
            await db.execute(
                select(TournamentEvent).where(_id_text_expr(TournamentEvent.id).in_(event_ids))
            )
        ).scalars().all()
        event_map = {event.id: event for event in event_rows}
    changed = False
    for s in sessions:
        if s.status in {"pending_invites", "ready_to_start"}:
            pending_count_stmt = select(func.count(TournamentChallengeParticipant.id)).where(
                _id_text_expr(TournamentChallengeParticipant.session_id) == _id_text_value(s.id),
                TournamentChallengeParticipant.invite_state == "pending",
            )
            pending_count = int((await db.execute(pending_count_stmt)).scalar_one() or 0)
            declined_count_stmt = select(func.count(TournamentChallengeParticipant.id)).where(
                _id_text_expr(TournamentChallengeParticipant.session_id) == _id_text_value(s.id),
                TournamentChallengeParticipant.invite_state == "declined",
            )
            declined_count = int((await db.execute(declined_count_stmt)).scalar_one() or 0)

            new_status = s.status
            if declined_count > 0:
                new_status = "cancelled"
            elif pending_count == 0:
                new_status = "ready_to_start"
            else:
                new_status = "pending_invites"

            if new_status != s.status:
                s.status = new_status
                changed = True

    if changed:
        await db.commit()

    return {
        "sessions": [
            {
                "id": s.id,
                "event_id": s.event_id,
                "event_type": _event_public_type(event_map.get(s.event_id), event_type=s.event_type),
                "event_title": event_map.get(s.event_id).title if event_map.get(s.event_id) else None,
                "creator_user_id": s.creator_user_id,
                "scheduled_at": s.scheduled_at,
                "status": s.status,
                "started_at": s.started_at,
                "auto_close_at": s.auto_close_at,
                "completed_at": s.completed_at,
                "can_control_session": s.creator_user_id == current_user.id,
            }
            for s in sessions
        ]
    }


@router.get("/bootstrap")
async def tournament_bootstrap(
    include_players: bool = Query(default=True),
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    await ensure_default_events(db)
    await auto_close_overdue_sessions(db)
    now = utcnow()

    # Events
    events_stmt = (
        select(TournamentEvent)
        .where(TournamentEvent.status == "active", TournamentEvent.end_at >= now)
        .order_by(TournamentEvent.start_at.asc())
    )
    events = (await db.execute(events_stmt)).scalars().all()
    events_out: list[dict[str, Any]] = []
    for event in events:
        events_out.append(
            {
                "id": event.id,
                "title": event.title,
                "event_type": _event_public_type(event),
                "description": event.description,
                "min_donation_cents": event.min_donation_cents,
                "currency": event.currency,
                "unlock_mode": event.unlock_mode,
                "start_at": event.start_at,
                "end_at": event.end_at,
                "is_unlocked": True,
                "tickets_left": None,
                "payment_optional": True,
                "read_only": False,
            }
        )

    # Sessions
    participant_stmt = select(TournamentChallengeParticipant.session_id).where(
        TournamentChallengeParticipant.user_id == current_user.id
    )
    session_ids = [sid for sid in (await db.execute(participant_stmt)).scalars().all()]
    sessions_out: list[dict[str, Any]] = []
    if session_ids:
        sessions = (
            await db.execute(
                select(TournamentChallengeSession)
                .where(_id_text_expr(TournamentChallengeSession.id).in_([_id_text_value(sid) for sid in session_ids]))
                .order_by(TournamentChallengeSession.scheduled_at.desc())
            )
        ).scalars().all()
        event_map: dict[str, TournamentEvent] = {}
        event_ids = sorted({_id_text_value(s.event_id) for s in sessions})
        if event_ids:
            event_rows = (
                await db.execute(
                    select(TournamentEvent).where(_id_text_expr(TournamentEvent.id).in_(event_ids))
                )
            ).scalars().all()
            event_map = {event.id: event for event in event_rows}
        changed = False
        for s in sessions:
            if s.status in {"pending_invites", "ready_to_start"}:
                pending_count_stmt = select(func.count(TournamentChallengeParticipant.id)).where(
                    _id_text_expr(TournamentChallengeParticipant.session_id) == _id_text_value(s.id),
                    TournamentChallengeParticipant.invite_state == "pending",
                )
                pending_count = int((await db.execute(pending_count_stmt)).scalar_one() or 0)
                declined_count_stmt = select(func.count(TournamentChallengeParticipant.id)).where(
                    _id_text_expr(TournamentChallengeParticipant.session_id) == _id_text_value(s.id),
                    TournamentChallengeParticipant.invite_state == "declined",
                )
                declined_count = int((await db.execute(declined_count_stmt)).scalar_one() or 0)
                new_status = s.status
                if declined_count > 0:
                    new_status = "cancelled"
                elif pending_count == 0:
                    new_status = "ready_to_start"
                else:
                    new_status = "pending_invites"
                if new_status != s.status:
                    s.status = new_status
                    changed = True
            sessions_out.append(
                {
                    "id": s.id,
                    "event_id": s.event_id,
                    "event_type": _event_public_type(event_map.get(s.event_id), event_type=s.event_type),
                    "event_title": event_map.get(s.event_id).title if event_map.get(s.event_id) else None,
                    "creator_user_id": s.creator_user_id,
                    "scheduled_at": s.scheduled_at,
                    "status": s.status,
                    "started_at": s.started_at,
                    "auto_close_at": s.auto_close_at,
                    "completed_at": s.completed_at,
                    "can_control_session": s.creator_user_id == current_user.id,
                }
            )
        if changed:
            await db.commit()

    # Inbox
    inbox_stmt = (
        select(TournamentInboxMessage)
        .where(TournamentInboxMessage.recipient_user_id == current_user.id)
        .order_by(TournamentInboxMessage.created_at.desc())
        .limit(200)
    )
    messages = (await db.execute(inbox_stmt)).scalars().all()
    inbox_out = [
        {
            "id": m.id,
            "sender_user_id": m.sender_user_id,
            "session_id": m.session_id,
            "related_score_id": m.related_score_id,
            "message_type": m.message_type,
            "title": m.title,
            "body": m.body,
            "status": m.status,
            "created_at": m.created_at,
        }
        for m in messages
    ]
    unread_inbox_count = sum(1 for m in messages if m.status == "unread")

    # Friend requests
    fr_stmt = (
        select(TournamentFriendRequest, User)
        .join(User, User.id == TournamentFriendRequest.sender_user_id)
        .where(
            TournamentFriendRequest.receiver_user_id == current_user.id,
            TournamentFriendRequest.status == "pending",
        )
        .order_by(TournamentFriendRequest.created_at.desc())
    )
    friend_request_table_available = True
    try:
        fr_rows = (await db.execute(fr_stmt)).all()
    except ProgrammingError as exc:
        if not _is_missing_relation_or_column_error(exc):
            raise
        await db.rollback()
        fr_rows = []
        friend_request_table_available = False
    friend_requests_out = [
        {
            "id": fr.id,
            "sender_user_id": fr.sender_user_id,
            "sender_username": sender.username,
            "sender_email": sender.email,
            "status": fr.status,
            "created_at": fr.created_at,
        }
        for fr, sender in fr_rows
    ]

    players_out: list[dict[str, Any]] = []
    if include_players:
        now = _naive_utc(utcnow()) or datetime.utcnow()
        users = (
            await db.execute(
                select(User)
                .where(
                    User.id != current_user.id,
                    User.role.in_(["guest", "subscriber", "admin", "admine"]),
                )
                .order_by(User.last_login.desc().nullslast(), User.id.desc())
                .limit(300)
            )
        ).scalars().all()

        for user in users:
            last_login = _naive_utc(user.last_login)
            is_online = (
                last_login is not None
                and (now - last_login).total_seconds() <= 600
            )
            friend_status = "none"
            friend_request_id = None
            if friend_request_table_available:
                fr_lookup_stmt = (
                    select(TournamentFriendRequest)
                    .where(
                        or_(
                            and_(
                                TournamentFriendRequest.sender_user_id == current_user.id,
                                TournamentFriendRequest.receiver_user_id == user.id,
                            ),
                            and_(
                                TournamentFriendRequest.sender_user_id == user.id,
                                TournamentFriendRequest.receiver_user_id == current_user.id,
                            ),
                        )
                    )
                    .order_by(TournamentFriendRequest.created_at.desc())
                    .limit(1)
                )
                try:
                    fr = (await db.execute(fr_lookup_stmt)).scalar_one_or_none()
                except ProgrammingError as exc:
                    if not _is_missing_relation_or_column_error(exc):
                        raise
                    await db.rollback()
                    fr = None
                    friend_request_table_available = False
                if fr:
                    friend_request_id = fr.id
                    if fr.status == "accepted":
                        friend_status = "friend"
                    elif fr.status == "pending":
                        if fr.sender_user_id == current_user.id:
                            friend_status = "outgoing_pending"
                        else:
                            friend_status = "incoming_pending"

            players_out.append(
                {
                    "id": user.id,
                    "username": user.username,
                    "email": user.email,
                    "club_affiliation": user.club_affiliation,
                    "profile_pic": user.profile_pic,
                    "role": user.role,
                    "is_online": is_online,
                    "last_login": user.last_login,
                    "friend_status": friend_status,
                    "friend_request_id": friend_request_id,
                }
            )

    return {
        "events": events_out,
        "sessions": sessions_out,
        "messages": inbox_out,
        "incoming_friend_requests": friend_requests_out,
        "players": players_out,
        "unread_inbox_count": unread_inbox_count,
    }


@router.get("/dashboard/bootstrap")
async def dashboard_bootstrap(
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    await auto_close_overdue_sessions(db)

    event_title_by_type = {
        str(cfg["event_type"]): str(cfg["title"])
        for cfg in DEFAULT_EVENT_CONFIGS
    }

    my_scores_stmt = (
        select(GolfScore)
        .where(GolfScore.user_id == current_user.id)
        .order_by(GolfScore.played_on.desc(), GolfScore.created_at.desc())
        .limit(30)
    )
    golf_round_scores = (await db.execute(my_scores_stmt)).scalars().all()

    latest_session_scores = (
        select(
            TournamentSessionScore.id.label("score_id"),
            TournamentSessionScore.session_id.label("session_id"),
            TournamentSessionScore.total_score.label("total_score"),
            TournamentSessionScore.status.label("score_status"),
            TournamentSessionScore.submitted_at.label("submitted_at"),
            TournamentSessionScore.reviewed_at.label("reviewed_at"),
            func.row_number()
            .over(
                partition_by=TournamentSessionScore.session_id,
                order_by=(
                    TournamentSessionScore.submitted_at.desc().nullslast(),
                    TournamentSessionScore.id.desc(),
                ),
            )
            .label("rn"),
        )
        .where(TournamentSessionScore.player_user_id == current_user.id)
        .subquery("latest_session_scores")
    )
    session_score_stmt = (
        select(
            latest_session_scores.c.score_id,
            latest_session_scores.c.session_id,
            latest_session_scores.c.total_score,
            latest_session_scores.c.score_status,
            latest_session_scores.c.submitted_at,
            latest_session_scores.c.reviewed_at,
            TournamentChallengeSession.event_type.label("event_type"),
            TournamentChallengeSession.status.label("session_status"),
            TournamentChallengeSession.scheduled_at.label("scheduled_at"),
            TournamentChallengeSession.started_at.label("started_at"),
            TournamentChallengeSession.completed_at.label("completed_at"),
            TournamentEvent.title.label("event_title"),
        )
        .join(
            TournamentChallengeSession,
            _id_text_expr(TournamentChallengeSession.id) == _id_text_expr(latest_session_scores.c.session_id),
        )
        .outerjoin(
            TournamentEvent,
            _id_text_expr(TournamentEvent.id) == _id_text_expr(TournamentChallengeSession.event_id),
        )
        .where(latest_session_scores.c.rn == 1)
        .order_by(latest_session_scores.c.submitted_at.desc().nullslast())
        .limit(30)
    )
    session_score_rows = (await db.execute(session_score_stmt)).all()

    latest_confirmed_scores = (
        select(
            TournamentSessionScore.player_user_id.label("player_user_id"),
            TournamentSessionScore.session_id.label("session_id"),
            TournamentSessionScore.total_score.label("total_score"),
            TournamentSessionScore.reviewed_at.label("reviewed_at"),
            func.row_number()
            .over(
                partition_by=(TournamentSessionScore.player_user_id, TournamentSessionScore.session_id),
                order_by=(
                    TournamentSessionScore.reviewed_at.desc().nullslast(),
                    TournamentSessionScore.submitted_at.desc().nullslast(),
                    TournamentSessionScore.id.desc(),
                ),
            )
            .label("rn"),
        )
        .where(TournamentSessionScore.status == "confirmed")
        .subquery("latest_confirmed_scores")
    )

    leaderboard_stmt = (
        select(
            latest_confirmed_scores.c.player_user_id.label("player_user_id"),
            User.username.label("username"),
            func.count(latest_confirmed_scores.c.session_id).label("rounds_played"),
            func.avg(latest_confirmed_scores.c.total_score).label("average_score"),
            func.min(latest_confirmed_scores.c.total_score).label("best_score"),
            func.max(latest_confirmed_scores.c.reviewed_at).label("last_round_at"),
        )
        .join(User, User.id == latest_confirmed_scores.c.player_user_id)
        .where(latest_confirmed_scores.c.rn == 1)
        .group_by(latest_confirmed_scores.c.player_user_id, User.username)
        .order_by(
            func.avg(latest_confirmed_scores.c.total_score).asc(),
            func.min(latest_confirmed_scores.c.total_score).asc(),
            func.max(latest_confirmed_scores.c.reviewed_at).desc(),
        )
        .limit(50)
    )
    leaderboard_rows = (await db.execute(leaderboard_stmt)).all()
    leaderboard: list[dict[str, Any]] = []
    for idx, row in enumerate(leaderboard_rows, start=1):
        avg_score = round(float(row.average_score or 0), 2)
        leaderboard.append(
            {
                "rank": idx,
                "player_user_id": int(row.player_user_id),
                "player_name": row.username,
                # Keep total_points for backward compatibility with older UI.
                "total_points": avg_score,
                "average_score": avg_score,
                "best_score": int(row.best_score or 0),
                "rounds_played": int(row.rounds_played or 0),
                "last_round_at": row.last_round_at,
            }
        )

    active_sessions_stmt = (
        select(TournamentChallengeSession)
        .where(TournamentChallengeSession.status == "in_progress")
        .order_by(TournamentChallengeSession.started_at.desc().nullslast())
        .limit(50)
    )
    active_sessions = (await db.execute(active_sessions_stmt)).scalars().all()

    live_events: list[dict[str, Any]] = []
    for session in active_sessions:
        participant_stmt = (
            select(TournamentChallengeParticipant, User)
            .join(User, User.id == TournamentChallengeParticipant.user_id)
            .where(
                _id_text_expr(TournamentChallengeParticipant.session_id) == _id_text_value(session.id),
                TournamentChallengeParticipant.invite_state == "accepted",
            )
            .order_by(User.username.asc())
        )
        participant_rows = (await db.execute(participant_stmt)).all()
        participants = [
            {
                "user_id": p.user_id,
                "name": user.username,
            }
            for p, user in participant_rows
        ]
        participant_ids = [p["user_id"] for p in participants]

        latest_score_lookup: dict[int, dict[str, Any]] = {}
        if participant_ids:
            score_stmt = (
                select(
                    TournamentSessionScore.player_user_id.label("player_user_id"),
                    TournamentSessionScore.total_score.label("live_total"),
                    TournamentSessionScore.submitted_at.label("latest_submit_at"),
                )
                .where(
                    _id_text_expr(TournamentSessionScore.session_id) == _id_text_value(session.id),
                    TournamentSessionScore.status.in_(["pending_confirmation", "confirmed"]),
                    TournamentSessionScore.player_user_id.in_(participant_ids),
                )
                .order_by(
                    TournamentSessionScore.player_user_id.asc(),
                    TournamentSessionScore.submitted_at.desc().nullslast(),
                    TournamentSessionScore.id.desc(),
                )
            )
            score_rows = (await db.execute(score_stmt)).all()
            for row in score_rows:
                pid = int(row.player_user_id)
                if pid in latest_score_lookup:
                    continue
                latest_score_lookup[pid] = {
                    "live_total": int(row.live_total) if row.live_total is not None else None,
                    "latest_submit_at": row.latest_submit_at,
                }

        live_player_scores = [
            {
                "user_id": p["user_id"],
                "name": p["name"],
                "live_total": latest_score_lookup.get(int(p["user_id"]), {}).get("live_total"),
                "last_submitted_at": latest_score_lookup.get(int(p["user_id"]), {}).get("latest_submit_at"),
            }
            for p in participants
        ]
        live_player_scores.sort(
            key=lambda x: (
                x["live_total"] is None,
                x["live_total"] if x["live_total"] is not None else 10**9,
                str(x["name"]).lower(),
            )
        )

        latest_update = None
        if latest_score_lookup:
            latest_update = max(
                (v.get("latest_submit_at") for v in latest_score_lookup.values() if v.get("latest_submit_at")),
                default=None,
            )

        event = (
            await db.execute(
                select(TournamentEvent).where(_id_text_expr(TournamentEvent.id) == _id_text_value(session.event_id))
            )
        ).scalar_one_or_none()
        event_title = event.title if event else session.event_type

        live_events.append(
            {
                "session_id": session.id,
                "event_id": session.event_id,
                "event_name": event_title,
                "event_type": session.event_type,
                "status": session.status,
                "started_at": session.started_at,
                "auto_close_at": session.auto_close_at,
                "latest_update_at": latest_update,
                "players": live_player_scores,
            }
        )

    combined_scores: list[dict[str, Any]] = []
    for s in golf_round_scores:
        played_at = None
        if s.played_on:
            played_at = datetime.combine(s.played_on, datetime.min.time())
        else:
            played_at = _naive_utc(s.created_at)
        combined_scores.append(
            {
                "id": s.id,
                "entry_type": "round",
                "title": s.course_name or "Golf Round",
                "event_name": None,
                "course_name": s.course_name,
                "score": int(s.score or 0),
                "played_on": s.played_on,
                "played_at": played_at,
                "is_verified": bool(s.is_verified),
                "score_status": "verified" if s.is_verified else "submitted",
                "source": s.source or "manual",
                "_sort_at": played_at or datetime.min,
            }
        )

    for row in session_score_rows:
        event_name = row.event_title or event_title_by_type.get(
            str(row.event_type), str(row.event_type)
        )
        played_at = (
            _naive_utc(row.reviewed_at)
            or _naive_utc(row.submitted_at)
            or _naive_utc(row.completed_at)
            or _naive_utc(row.started_at)
            or _naive_utc(row.scheduled_at)
        )
        combined_scores.append(
            {
                "id": row.score_id,
                "session_id": row.session_id,
                "entry_type": "event",
                "title": event_name,
                "event_name": event_name,
                "event_type": row.event_type,
                "session_status": row.session_status,
                "score": int(row.total_score or 0),
                "played_on": played_at.date() if played_at else None,
                "played_at": played_at,
                "is_verified": str(row.score_status) == "confirmed",
                "score_status": row.score_status,
                "source": "event_session",
                "_sort_at": played_at or datetime.min,
            }
        )

    combined_scores.sort(
        key=lambda item: item.get("_sort_at") or datetime.min,
        reverse=True,
    )
    for score in combined_scores:
        score.pop("_sort_at", None)

    jackpot_winners: list[dict[str, Any]] = []
    weekly_draw_winners: list[dict[str, Any]] = []
    try:
        latest_monthly_draw = (
            await db.execute(
                select(GolfDraw)
                .where(
                    GolfDraw.status == "completed",
                    ~GolfDraw.month_key.like("%-W%"),
                )
                .order_by(
                    GolfDraw.completed_at.desc().nullslast(),
                    GolfDraw.created_at.desc(),
                )
                .limit(1)
            )
        ).scalar_one_or_none()
        if latest_monthly_draw:
            winner_rows = (
                await db.execute(
                    select(GolfDrawEntry, User)
                    .join(User, User.id == GolfDrawEntry.user_id)
                    .where(
                        GolfDrawEntry.draw_id == latest_monthly_draw.id,
                        GolfDrawEntry.is_winner.is_(True),
                    )
                )
            ).all()
            jackpot_items: list[dict[str, Any]] = []
            secondary_items: list[dict[str, Any]] = []
            for entry, user in winner_rows:
                breakdown = entry.score_window if isinstance(entry.score_window, dict) else {}
                payout_cents = int((breakdown or {}).get("payout_cents") or 0)
                item = {
                    "draw_id": latest_monthly_draw.id,
                    "draw_key": latest_monthly_draw.month_key,
                    "completed_at": latest_monthly_draw.completed_at,
                    "user_id": int(user.id),
                    "username": user.username,
                    "payout_cents": payout_cents,
                    "payout_usd": round(payout_cents / 100.0, 2),
                    "match_count": int(entry.match_count or 0),
                    "match_label": (
                        (breakdown or {}).get("tier_label")
                        or f"{int(entry.match_count or 0)}-Number Match"
                    ),
                }
                if int(entry.match_count or 0) == 5:
                    jackpot_items.append(item)
                elif int(entry.match_count or 0) in {3, 4}:
                    secondary_items.append(item)

            jackpot_items.sort(
                key=lambda x: (
                    -int(x.get("payout_cents") or 0),
                    str(x.get("username") or "").lower(),
                )
            )
            for idx, item in enumerate(jackpot_items[:3], start=1):
                item["position"] = idx
                jackpot_winners.append(item)

            secondary_items.sort(
                key=lambda x: (
                    -int(x.get("match_count") or 0),
                    -int(x.get("payout_cents") or 0),
                    str(x.get("username") or "").lower(),
                )
            )
            for idx, item in enumerate(secondary_items[:6], start=1):
                item["position"] = idx
                weekly_draw_winners.append(item)
    except Exception:
        # Keep dashboard resilient when draw schema/data is unavailable.
        jackpot_winners = []
        weekly_draw_winners = []

    return {
        "my_scores": combined_scores[:50],
        "leaderboard": leaderboard,
        "live_events": live_events,
        "jackpot_winners": jackpot_winners,
        "weekly_draw_winners": weekly_draw_winners,
        "generated_at": utcnow(),
    }


@router.get("/inbox")
async def my_inbox(
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    await auto_close_overdue_sessions(db)
    stmt = (
        select(TournamentInboxMessage)
        .where(TournamentInboxMessage.recipient_user_id == current_user.id)
        .order_by(TournamentInboxMessage.created_at.desc())
        .limit(200)
    )
    messages = (await db.execute(stmt)).scalars().all()
    return {
        "messages": [
            {
                "id": m.id,
                "sender_user_id": m.sender_user_id,
                "session_id": m.session_id,
                "related_score_id": m.related_score_id,
                "message_type": m.message_type,
                "title": m.title,
                "body": m.body,
                "status": m.status,
                "created_at": m.created_at,
            }
            for m in messages
        ]
    }


@router.post("/inbox/{message_id}/action")
async def action_inbox_message(
    message_id: str,
    payload: InviteActionRequest,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = select(TournamentInboxMessage).where(
        _id_text_expr(TournamentInboxMessage.id) == _id_text_value(message_id),
        TournamentInboxMessage.recipient_user_id == current_user.id,
    )
    message = (await db.execute(stmt)).scalar_one_or_none()
    if not message:
        raise HTTPException(status_code=404, detail="Message not found")
    if message.message_type != "invite":
        raise HTTPException(status_code=409, detail="Only invite messages support action")
    if not message.session_id:
        raise HTTPException(status_code=409, detail="Invite missing session reference")

    participant_stmt = select(TournamentChallengeParticipant).where(
        _id_text_expr(TournamentChallengeParticipant.session_id) == _id_text_value(message.session_id),
        TournamentChallengeParticipant.user_id == current_user.id,
    )
    participant = (await db.execute(participant_stmt)).scalar_one_or_none()
    if not participant:
        raise HTTPException(status_code=404, detail="Participant record not found")

    session_stmt = select(TournamentChallengeSession).where(
        _id_text_expr(TournamentChallengeSession.id) == _id_text_value(message.session_id)
    )
    session = (await db.execute(session_stmt)).scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    if payload.action == "accept":
        participant.invite_state = "accepted"
        participant.joined_at = utcnow()
        message.status = "accepted"
    else:
        participant.invite_state = "declined"
        message.status = "declined"

    message.actioned_at = utcnow()
    await db.flush()

    pending_count_stmt = select(func.count(TournamentChallengeParticipant.id)).where(
        _id_text_expr(TournamentChallengeParticipant.session_id) == _id_text_value(session.id),
        TournamentChallengeParticipant.invite_state == "pending",
    )
    pending_count = int((await db.execute(pending_count_stmt)).scalar_one() or 0)
    declined_count_stmt = select(func.count(TournamentChallengeParticipant.id)).where(
        _id_text_expr(TournamentChallengeParticipant.session_id) == _id_text_value(session.id),
        TournamentChallengeParticipant.invite_state == "declined",
    )
    declined_count = int((await db.execute(declined_count_stmt)).scalar_one() or 0)
    if pending_count == 0:
        if declined_count > 0:
            session.status = "cancelled"
        else:
            session.status = "ready_to_start"
    elif session.status == "ready_to_start":
        session.status = "pending_invites"

    db.add(
        TournamentInboxMessage(
            recipient_user_id=session.creator_user_id,
            sender_user_id=current_user.id,
            session_id=session.id,
            message_type="system",
            title=f"Invite {payload.action.title()}",
            body=f"{current_user.username} has {payload.action}ed your challenge invite.",
            status="unread",
        )
    )

    await db.commit()
    return {"ok": True, "message_id": message.id, "action": payload.action, "session_status": session.status}


@router.post("/sessions/{session_id}/start")
async def start_challenge_session(
    session_id: str,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    await auto_close_overdue_sessions(db)
    session = (
        await db.execute(
            select(TournamentChallengeSession).where(_id_text_expr(TournamentChallengeSession.id) == _id_text_value(session_id))
        )
    ).scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    if current_user.id != session.creator_user_id:
        raise HTTPException(status_code=403, detail="Only the session creator can start the session")
    if session.status != "ready_to_start":
        raise HTTPException(status_code=409, detail=f"Session cannot be started from status '{session.status}'")

    event = (
        await db.execute(
            select(TournamentEvent).where(_id_text_expr(TournamentEvent.id) == _id_text_value(session.event_id))
        )
    ).scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")
    now = utcnow()
    if event.status != "active" or now < event.start_at or now > event.end_at:
        raise HTTPException(status_code=409, detail="Event is not active for session start")

    session.status = "in_progress"
    session.started_at = now
    session.auto_close_at = now + timedelta(days=2)
    await db.commit()
    return {
        "ok": True,
        "session_id": session.id,
        "status": session.status,
        "started_at": session.started_at,
        "auto_close_at": session.auto_close_at,
    }


@router.post("/sessions/{session_id}/end")
async def end_challenge_session(
    session_id: str,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    await auto_close_overdue_sessions(db)
    session = (
        await db.execute(
            select(TournamentChallengeSession).where(_id_text_expr(TournamentChallengeSession.id) == _id_text_value(session_id))
        )
    ).scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    if current_user.id != session.creator_user_id:
        raise HTTPException(status_code=403, detail="Only the session creator can end the session")

    if session.status != "in_progress":
        raise HTTPException(status_code=409, detail=f"Session cannot be ended from status '{session.status}'")

    session.status = "completed"
    session.completed_at = utcnow()
    await db.commit()
    return {
        "ok": True,
        "session_id": session.id,
        "status": session.status,
        "completed_at": session.completed_at,
    }


@router.post("/inbox/mark-seen")
async def mark_inbox_seen(
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    unread_stmt = (
        select(TournamentInboxMessage)
        .where(
            TournamentInboxMessage.recipient_user_id == current_user.id,
            TournamentInboxMessage.status == "unread",
        )
    )
    unread_messages = (await db.execute(unread_stmt)).scalars().all()
    for m in unread_messages:
        m.status = "read"
        m.actioned_at = m.actioned_at or utcnow()
    await db.commit()
    return {"ok": True, "marked_count": len(unread_messages)}


@router.post("/inbox/clear")
async def clear_inbox(
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    delete_stmt = delete(TournamentInboxMessage).where(
        TournamentInboxMessage.recipient_user_id == current_user.id
    )
    result = await db.execute(delete_stmt)
    await db.commit()
    return {"ok": True, "cleared_count": int(result.rowcount or 0)}


def _resolve_marker_for_session(
    session: TournamentChallengeSession,
    accepted_participants: list[TournamentChallengeParticipant],
    player_user_id: int,
    marker_user_id: int | None,
) -> int:
    accepted_ids = [p.user_id for p in accepted_participants]
    if player_user_id not in accepted_ids:
        raise HTTPException(status_code=403, detail="Player is not accepted in this session")

    other_ids = [uid for uid in accepted_ids if uid != player_user_id]
    if session.event_type == "one_on_one":
        if len(other_ids) != 1:
            raise HTTPException(status_code=409, detail="1v1 session requires one opponent")
        return other_ids[0]

    if marker_user_id and marker_user_id in other_ids:
        return marker_user_id
    if other_ids:
        return other_ids[0]
    return player_user_id


@router.post("/sessions/{session_id}/scores", status_code=status.HTTP_201_CREATED)
async def submit_session_score(
    session_id: str,
    payload: SessionScoreSubmitRequest,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    await auto_close_overdue_sessions(db)
    session = (
        await db.execute(
            select(TournamentChallengeSession).where(
                _id_text_expr(TournamentChallengeSession.id) == _id_text_value(session_id)
            )
        )
    ).scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    if session.status != "in_progress":
        raise HTTPException(status_code=409, detail="Session must be in progress")

    participants_stmt = select(TournamentChallengeParticipant).where(
        _id_text_expr(TournamentChallengeParticipant.session_id) == _id_text_value(session_id),
        TournamentChallengeParticipant.invite_state == "accepted",
    )
    accepted_participants = (await db.execute(participants_stmt)).scalars().all()
    marker_id = _resolve_marker_for_session(session, accepted_participants, current_user.id, payload.marker_user_id)
    finalized_at = utcnow()

    # New score submissions should replace any pending unreviewed submission
    # for this same player/session.
    pending_scores_stmt = select(TournamentSessionScore).where(
        _id_text_expr(TournamentSessionScore.session_id) == _id_text_value(session_id),
        TournamentSessionScore.player_user_id == current_user.id,
        TournamentSessionScore.status == "pending_confirmation",
    )
    pending_scores = (await db.execute(pending_scores_stmt)).scalars().all()
    if pending_scores:
        superseded_at = utcnow()
        pending_ids: list[str] = []
        for pending in pending_scores:
            pending.status = "rejected"
            pending.reviewed_at = superseded_at
            pending.rejection_reason = "Superseded by a newer score submission."
            pending_ids.append(pending.id)

        stale_inbox_stmt = select(TournamentInboxMessage).where(
            TournamentInboxMessage.related_score_id.in_(pending_ids),
            TournamentInboxMessage.message_type == "score_confirmation_request",
            TournamentInboxMessage.status == "unread",
        )
        stale_messages = (await db.execute(stale_inbox_stmt)).scalars().all()
        for message in stale_messages:
            message.status = "read"

    score = TournamentSessionScore(
        session_id=session_id,
        player_user_id=current_user.id,
        marker_user_id=marker_id,
        total_score=payload.total_score,
        holes_played=payload.holes_played,
        total_putts=payload.total_putts,
        gir_count=payload.gir_count,
        fairways_hit_count=payload.fairways_hit_count,
        penalties_total=payload.penalties_total,
        notes=(payload.notes or "").strip() or None,
        status="confirmed",
        reviewed_at=finalized_at,
    )
    db.add(score)
    await db.flush()

    if payload.holes_played is not None and payload.holes_played not in (9, 18):
        raise HTTPException(status_code=400, detail="holes_played must be either 9 or 18")

    hole_values = payload.hole_scores[:18]
    expected_holes = payload.holes_played
    if expected_holes is None and hole_values:
        expected_holes = 9 if len(hole_values) <= 9 else 18
    if expected_holes is not None and hole_values and len(hole_values) != expected_holes:
        raise HTTPException(
            status_code=400,
            detail=f"hole_scores length must match holes_played ({expected_holes})",
        )
    for idx, value in enumerate(hole_values):
        if value < 1 or value > 15:
            raise HTTPException(status_code=400, detail="Each hole score must be between 1 and 15")
        db.add(
            TournamentSessionScoreHole(
                score_id=score.id,
                hole_number=idx + 1,
                score=value,
            )
        )

    if hole_values and sum(hole_values) != payload.total_score:
        raise HTTPException(
            status_code=400,
            detail="total_score must equal sum of hole_scores when hole_scores are provided",
        )
    if expected_holes is not None and payload.gir_count is not None and payload.gir_count > expected_holes:
        raise HTTPException(status_code=400, detail="gir_count cannot exceed holes_played")
    if (
        expected_holes is not None
        and payload.fairways_hit_count is not None
        and payload.fairways_hit_count > expected_holes
    ):
        raise HTTPException(status_code=400, detail="fairways_hit_count cannot exceed holes_played")

    existing_entries = (
        await db.execute(
            select(TournamentScoreboardEntry)
            .where(
                TournamentScoreboardEntry.session_id == score.session_id,
                TournamentScoreboardEntry.player_user_id == score.player_user_id,
            )
            .order_by(TournamentScoreboardEntry.confirmed_at.desc())
        )
    ).scalars().all()
    if not existing_entries:
        db.add(
            TournamentScoreboardEntry(
                session_id=score.session_id,
                score_id=score.id,
                player_user_id=score.player_user_id,
                total_score=score.total_score,
                confirmed_at=finalized_at,
            )
        )
    else:
        primary = existing_entries[0]
        primary.score_id = score.id
        primary.total_score = score.total_score
        primary.confirmed_at = finalized_at
        for extra in existing_entries[1:]:
            await db.delete(extra)

    await db.commit()
    return {"score_id": score.id, "status": score.status, "marker_user_id": marker_id}


@router.post("/scores/{score_id}/confirm")
async def confirm_session_score(
    score_id: str,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    score = (await db.execute(select(TournamentSessionScore).where(TournamentSessionScore.id == score_id))).scalar_one_or_none()
    if not score:
        raise HTTPException(status_code=404, detail="Score not found")
    if score.marker_user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only assigned marker can confirm")
    if score.status != "pending_confirmation":
        raise HTTPException(status_code=409, detail="Score is not pending confirmation")

    score.status = "confirmed"
    score.reviewed_at = utcnow()

    existing_entries = (
        await db.execute(
            select(TournamentScoreboardEntry)
            .where(
                TournamentScoreboardEntry.session_id == score.session_id,
                TournamentScoreboardEntry.player_user_id == score.player_user_id,
            )
            .order_by(TournamentScoreboardEntry.confirmed_at.desc())
        )
    ).scalars().all()
    if not existing_entries:
        db.add(
            TournamentScoreboardEntry(
                session_id=score.session_id,
                score_id=score.id,
                player_user_id=score.player_user_id,
                total_score=score.total_score,
            )
        )
    else:
        primary = existing_entries[0]
        primary.score_id = score.id
        primary.total_score = score.total_score
        primary.confirmed_at = utcnow()
        for extra in existing_entries[1:]:
            await db.delete(extra)

    db.add(
        TournamentInboxMessage(
            recipient_user_id=score.player_user_id,
            sender_user_id=current_user.id,
            session_id=score.session_id,
            related_score_id=score.id,
            message_type="score_confirmation_result",
            title="Score Confirmed",
            body=f"Your score of {score.total_score} has been confirmed by marker.",
            status="unread",
        )
    )

    await db.commit()
    return {"score_id": score.id, "status": score.status}


@router.post("/scores/{score_id}/reject")
async def reject_session_score(
    score_id: str,
    payload: SessionScoreReviewRequest,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    score = (await db.execute(select(TournamentSessionScore).where(TournamentSessionScore.id == score_id))).scalar_one_or_none()
    if not score:
        raise HTTPException(status_code=404, detail="Score not found")
    if score.marker_user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only assigned marker can reject")
    if score.status != "pending_confirmation":
        raise HTTPException(status_code=409, detail="Score is not pending confirmation")

    score.status = "rejected"
    score.reviewed_at = utcnow()
    score.rejection_reason = (payload.reason or "").strip() or "No reason provided"

    db.add(
        TournamentInboxMessage(
            recipient_user_id=score.player_user_id,
            sender_user_id=current_user.id,
            session_id=score.session_id,
            related_score_id=score.id,
            message_type="score_confirmation_result",
            title="Score Rejected",
            body=f"Your score was rejected by marker. Reason: {score.rejection_reason}",
            status="unread",
        )
    )

    await db.commit()
    return {"score_id": score.id, "status": score.status, "reason": score.rejection_reason}


@router.get("/sessions/{session_id}/scoreboard")
async def session_scoreboard(
    session_id: str,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    await auto_close_overdue_sessions(db)
    participant = (
        await db.execute(
            select(TournamentChallengeParticipant).where(
                _id_text_expr(TournamentChallengeParticipant.session_id) == _id_text_value(session_id),
                TournamentChallengeParticipant.user_id == current_user.id,
            )
        )
    ).scalar_one_or_none()
    if not participant and not _is_admin_role(current_user.role):
        raise HTTPException(status_code=403, detail="Not a participant in this session")

    entry_rows = (
        await db.execute(
            select(TournamentScoreboardEntry, TournamentSessionScore)
            .join(
                TournamentSessionScore,
                _id_text_expr(TournamentSessionScore.id) == _id_text_expr(TournamentScoreboardEntry.score_id),
            )
            .where(_id_text_expr(TournamentScoreboardEntry.session_id) == _id_text_value(session_id))
            .order_by(TournamentScoreboardEntry.confirmed_at.desc().nullslast())
        )
    ).all()

    latest_per_player: dict[int, tuple[TournamentScoreboardEntry, TournamentSessionScore]] = {}
    for entry, score in entry_rows:
        pid = int(entry.player_user_id)
        if pid not in latest_per_player:
            latest_per_player[pid] = (entry, score)

    deduped_rows = list(latest_per_player.values())
    deduped_rows.sort(
        key=lambda pair: (
            int(pair[0].total_score or 10**9),
            pair[0].confirmed_at or datetime.max.replace(tzinfo=timezone.utc),
        )
    )

    return {
        "session_id": session_id,
        "entries": [
            {
                "player_user_id": entry.player_user_id,
                "total_score": entry.total_score,
                "holes_played": score.holes_played,
                "total_putts": score.total_putts,
                "gir_count": score.gir_count,
                "fairways_hit_count": score.fairways_hit_count,
                "penalties_total": score.penalties_total,
                "confirmed_at": entry.confirmed_at,
            }
            for entry, score in deduped_rows
        ],
    }


@router.get("/courses")
async def list_courses(
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = select(TournamentCourse).order_by(TournamentCourse.name.asc())
    courses = (await db.execute(stmt)).scalars().all()
    return {
        "courses": [
            {
                "id": c.id,
                "name": c.name,
                "location": c.location,
                "course_rating": float(c.course_rating),
                "slope_rating": c.slope_rating,
                "holes_count": c.holes_count,
            }
            for c in courses
        ]
    }


@router.post("/courses", status_code=status.HTTP_201_CREATED)
async def create_course(
    payload: CourseCreateRequest,
    current_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    holes_count = 9 if payload.holes_count <= 9 else 18
    course = TournamentCourse(
        name=payload.name.strip(),
        location=(payload.location or "").strip() or None,
        course_rating=payload.course_rating,
        slope_rating=payload.slope_rating,
        holes_count=holes_count,
    )
    db.add(course)
    await db.flush()

    for hole in range(1, holes_count + 1):
        db.add(
            TournamentCourseHole(
                course_id=course.id,
                hole_number=hole,
                par=payload.default_par,
                yardage=None,
            )
        )

    await db.commit()
    return {
        "id": course.id,
        "name": course.name,
        "holes_count": course.holes_count,
        "created_by": current_user.id,
    }


@router.post("/rounds", status_code=status.HTTP_201_CREATED)
async def create_round(
    payload: RoundCreateRequest,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    course_stmt = select(TournamentCourse).where(TournamentCourse.id == payload.course_id)
    course = (await db.execute(course_stmt)).scalar_one_or_none()
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")

    tournament_round = TournamentRound(
        player_user_id=current_user.id,
        course_id=payload.course_id,
        round_type=payload.round_type,
        played_at=payload.played_at,
        status="draft",
        marker_user_id=payload.marker_user_id,
        source=payload.source,
    )
    db.add(tournament_round)
    await db.flush()
    await create_audit(
        db,
        tournament_round.id,
        current_user.id,
        "create",
        {"course_id": payload.course_id, "round_type": payload.round_type, "played_at": payload.played_at.isoformat()},
    )
    await db.commit()
    return {"id": tournament_round.id, "status": tournament_round.status, "round_type": tournament_round.round_type}


@router.put("/rounds/{round_id}/holes/{hole_no}")
async def upsert_round_hole(
    round_id: str,
    hole_no: int,
    payload: RoundHoleUpsertRequest,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    if hole_no < 1 or hole_no > 18:
        raise HTTPException(status_code=400, detail="hole_no must be between 1 and 18")

    tournament_round = await get_round_for_user_or_admin(db, round_id, current_user)
    if tournament_round.status in {"locked", "verified", "submitted"}:
        raise HTTPException(status_code=409, detail="Round is not editable in current status")

    if hole_no > expected_holes(tournament_round.round_type):
        raise HTTPException(status_code=400, detail="Hole out of range for this round type")

    hole_stmt = select(TournamentRoundHole).where(
        and_(TournamentRoundHole.round_id == round_id, TournamentRoundHole.hole_number == hole_no)
    )
    hole = (await db.execute(hole_stmt)).scalar_one_or_none()
    if hole:
        hole.par = payload.par
        hole.strokes = payload.strokes
        hole.putts = payload.putts
        hole.fairway_hit = payload.fairway_hit
        hole.gir = payload.gir
        hole.sand_save = payload.sand_save
        hole.penalties = payload.penalties
    else:
        db.add(
            TournamentRoundHole(
                round_id=round_id,
                hole_number=hole_no,
                par=payload.par,
                strokes=payload.strokes,
                putts=payload.putts,
                fairway_hit=payload.fairway_hit,
                gir=payload.gir,
                sand_save=payload.sand_save,
                penalties=payload.penalties,
            )
        )

    await create_audit(db, round_id, current_user.id, "update_hole", {"hole_number": hole_no})
    await db.commit()
    return {"ok": True, "round_id": round_id, "hole_number": hole_no}


@router.get("/rounds/{round_id}")
async def get_round_detail(
    round_id: str,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    tournament_round = await get_round_for_user_or_admin(db, round_id, current_user)
    holes = await load_round_holes(db, round_id)
    totals = await compute_round_totals(db, tournament_round)
    return {
        "round": {
            "id": tournament_round.id,
            "status": tournament_round.status,
            "player_user_id": tournament_round.player_user_id,
            "course_id": tournament_round.course_id,
            "round_type": tournament_round.round_type,
            "played_at": tournament_round.played_at,
            "marker_user_id": tournament_round.marker_user_id,
            "gross_score": tournament_round.gross_score,
            "total_putts": tournament_round.total_putts,
            "gir_count": tournament_round.gir_count,
            "fairways_hit_count": tournament_round.fairways_hit_count,
            "penalties_total": tournament_round.penalties_total,
        },
        "progress": {"holes_completed": len(holes), "holes_expected": expected_holes(tournament_round.round_type)},
        "totals_preview": totals,
        "holes": [
            {
                "hole_number": h.hole_number,
                "par": h.par,
                "strokes": h.strokes,
                "putts": h.putts,
                "fairway_hit": h.fairway_hit,
                "gir": h.gir,
                "sand_save": h.sand_save,
                "penalties": h.penalties,
            }
            for h in holes
        ],
    }


@router.post("/rounds/{round_id}/submit")
async def submit_round(
    round_id: str,
    payload: RoundSubmitRequest,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    tournament_round = await get_round_for_user_or_admin(db, round_id, current_user)
    if tournament_round.player_user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only round owner can submit")
    if tournament_round.status != "draft":
        raise HTTPException(status_code=409, detail="Only draft rounds can be submitted")

    holes = await load_round_holes(db, round_id)
    needed = expected_holes(tournament_round.round_type)
    if len(holes) != needed:
        raise HTTPException(status_code=400, detail=f"Round requires exactly {needed} holes before submit")
    if payload.marker_user_id == current_user.id:
        raise HTTPException(status_code=400, detail="Marker must be a different player")

    totals = await compute_round_totals(db, tournament_round)
    tournament_round.marker_user_id = payload.marker_user_id
    tournament_round.submitted_at = utcnow()
    tournament_round.status = "submitted"
    tournament_round.gross_score = totals["gross_score"]
    tournament_round.total_putts = totals["total_putts"]
    tournament_round.gir_count = totals["gir_count"]
    tournament_round.fairways_hit_count = totals["fairways_hit_count"]
    tournament_round.penalties_total = totals["penalties_total"]

    verification_stmt = select(TournamentRoundVerification).where(TournamentRoundVerification.round_id == round_id)
    verification = (await db.execute(verification_stmt)).scalar_one_or_none()
    if verification:
        verification.marker_user_id = payload.marker_user_id
        verification.marker_confirmed = False
        verification.marker_confirmed_at = None
        verification.rejection_reason = None
    else:
        db.add(TournamentRoundVerification(round_id=round_id, marker_user_id=payload.marker_user_id, marker_confirmed=False))

    await create_audit(db, round_id, current_user.id, "submit", {"marker_user_id": payload.marker_user_id})
    await db.commit()
    return {"ok": True, "round_id": round_id, "status": tournament_round.status}


@router.post("/rounds/{round_id}/marker-confirm")
async def marker_confirm_round(
    round_id: str,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = select(TournamentRound).where(TournamentRound.id == round_id)
    tournament_round = (await db.execute(stmt)).scalar_one_or_none()
    if not tournament_round:
        raise HTTPException(status_code=404, detail="Round not found")
    if tournament_round.status != "submitted":
        raise HTTPException(status_code=409, detail="Round must be in submitted state")

    is_admin = _is_admin_role(current_user.role)
    if not is_admin and tournament_round.marker_user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only assigned marker can confirm this round")

    verification_stmt = select(TournamentRoundVerification).where(TournamentRoundVerification.round_id == round_id)
    verification = (await db.execute(verification_stmt)).scalar_one_or_none()
    if not verification:
        raise HTTPException(status_code=409, detail="Verification record missing")

    verification.marker_confirmed = True
    verification.marker_confirmed_at = utcnow()
    verification.rejection_reason = None
    tournament_round.status = "verified"
    tournament_round.verified_at = utcnow()

    await create_audit(db, round_id, current_user.id, "verify", {"marker_confirmed": True})
    await db.commit()
    return {"ok": True, "round_id": round_id, "status": tournament_round.status}


@router.post("/rounds/{round_id}/reject")
async def reject_round(
    round_id: str,
    payload: RoundRejectRequest,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = select(TournamentRound).where(TournamentRound.id == round_id)
    tournament_round = (await db.execute(stmt)).scalar_one_or_none()
    if not tournament_round:
        raise HTTPException(status_code=404, detail="Round not found")

    is_admin = _is_admin_role(current_user.role)
    if not (is_admin or tournament_round.marker_user_id == current_user.id):
        raise HTTPException(status_code=403, detail="Only marker or admin can reject a round")

    verification_stmt = select(TournamentRoundVerification).where(TournamentRoundVerification.round_id == round_id)
    verification = (await db.execute(verification_stmt)).scalar_one_or_none()
    if not verification:
        verification = TournamentRoundVerification(
            round_id=round_id,
            marker_user_id=tournament_round.marker_user_id or current_user.id,
            marker_confirmed=False,
        )
        db.add(verification)
    verification.rejection_reason = payload.reason
    verification.marker_confirmed = False
    verification.marker_confirmed_at = None

    tournament_round.status = "rejected"
    db.add(
        TournamentFraudFlag(
            user_id=tournament_round.player_user_id,
            round_id=tournament_round.id,
            flag_type="marker_rejected",
            severity="medium",
            details={"reason": payload.reason},
        )
    )
    await upsert_trust_score(db, tournament_round.player_user_id)
    await create_audit(db, round_id, current_user.id, "reject", {"reason": payload.reason})
    await db.commit()
    return {"ok": True, "round_id": round_id, "status": tournament_round.status}


@router.post("/rounds/{round_id}/lock")
async def lock_round(
    round_id: str,
    payload: RoundLockRequest,
    current_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = select(TournamentRound).where(TournamentRound.id == round_id)
    tournament_round = (await db.execute(stmt)).scalar_one_or_none()
    if not tournament_round:
        raise HTTPException(status_code=404, detail="Round not found")
    if tournament_round.status != "verified":
        raise HTTPException(status_code=409, detail="Only verified rounds can be locked")

    tournament_round.status = "locked"
    tournament_round.locked_at = utcnow()
    await flag_outlier_if_needed(db, tournament_round)
    await upsert_trust_score(db, tournament_round.player_user_id)
    await create_audit(db, round_id, current_user.id, "lock", {"reason": (payload.reason or "").strip() or "admin_lock"})
    await db.commit()
    return {"ok": True, "round_id": round_id, "status": tournament_round.status}


@router.post("/ratings/recompute")
async def recompute_rating(
    user_id: int | None = Query(default=None, ge=1),
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    target_user_id = user_id or current_user.id
    is_admin = _is_admin_role(current_user.role)
    if target_user_id != current_user.id and not is_admin:
        raise HTTPException(status_code=403, detail="Only admin can recompute for another user")

    rounds_stmt = (
        select(TournamentRound)
        .where(
            TournamentRound.player_user_id == target_user_id,
            TournamentRound.status == "locked",
            TournamentRound.gross_score.isnot(None),
        )
        .order_by(TournamentRound.played_at.desc())
        .limit(20)
    )
    locked_rounds = list((await db.execute(rounds_stmt)).scalars().all())
    if not locked_rounds:
        raise HTTPException(status_code=404, detail="No locked rounds available for rating")

    round_ids = [r.id for r in locked_rounds]
    holes_stmt = select(TournamentRoundHole).where(TournamentRoundHole.round_id.in_(round_ids))
    holes = list((await db.execute(holes_stmt)).scalars().all())

    scores = [float(r.gross_score or 0) for r in locked_rounds]
    avg_score = sum(scores) / len(scores)
    std_dev = pstdev(scores) if len(scores) > 1 else 0.0

    gir_total = sum(1 for h in holes if h.gir)
    fairways_total = sum(1 for h in holes if h.fairway_hit is True)
    par45_total = sum(1 for h in holes if h.par in (4, 5))
    putts_total = sum(h.putts for h in holes)

    gir_pct = (gir_total / max(1, len(holes))) * 100.0
    fairways_pct = (fairways_total / max(1, par45_total)) * 100.0
    putts_per_round = putts_total / max(1, len(locked_rounds))

    profile_stmt = select(TournamentPlayerProfile).where(TournamentPlayerProfile.user_id == target_user_id)
    profile = (await db.execute(profile_stmt)).scalar_one_or_none()
    handicap_index = to_float(profile.handicap_index if profile else None, 20.0)

    handicap_score = normalize_inverse(handicap_index, best=0, worst=36)
    recent_form_score = normalize_inverse(avg_score, best=68, worst=110)
    gir_score = normalize_direct(gir_pct, best=20, worst=70)
    fairways_score = normalize_direct(fairways_pct, best=20, worst=80)
    strokes_gained_proxy = normalize_inverse(avg_score, best=68, worst=110)
    consistency_score = normalize_inverse(std_dev, best=1, worst=12)
    putting_score = normalize_inverse(putts_per_round, best=24, worst=42)

    rating = (
        0.30 * handicap_score
        + 0.20 * recent_form_score
        + 0.15 * gir_score
        + 0.10 * fairways_score
        + 0.10 * strokes_gained_proxy
        + 0.10 * consistency_score
        + 0.05 * putting_score
    )
    confidence = clamp01_to_100(min(100.0, len(locked_rounds) * 8.0 + 20.0))

    snapshot = TournamentPlayerMetricSnapshot(
        user_id=target_user_id,
        as_of=utcnow(),
        rounds_used=len(locked_rounds),
        avg_score=Decimal(str(round(avg_score, 2))),
        handicap_differential_avg=Decimal("0.00"),
        gir_pct=Decimal(str(round(gir_pct, 2))),
        fairways_hit_pct=Decimal(str(round(fairways_pct, 2))),
        putts_per_round=Decimal(str(round(putts_per_round, 2))),
        std_dev_score=Decimal(str(round(std_dev, 2))),
        recent_form_score=Decimal(str(round(recent_form_score, 2))),
        strokes_gained_total=Decimal(str(round(strokes_gained_proxy, 2))),
        confidence_score=Decimal(str(round(confidence, 2))),
    )
    db.add(snapshot)

    db.add(
        TournamentPlayerRating(
            user_id=target_user_id,
            as_of=utcnow(),
            rating_formula_version="v1.0-proxy",
            rating_score=Decimal(str(round(rating, 2))),
            confidence_score=Decimal(str(round(confidence, 2))),
        )
    )
    await upsert_trust_score(db, target_user_id)
    await db.commit()
    return {
        "user_id": target_user_id,
        "rating_score": round(rating, 2),
        "confidence_score": round(confidence, 2),
        "rounds_used": len(locked_rounds),
        "formula_version": "v1.0-proxy",
    }


@router.get("/players/{user_id}/metrics")
async def get_player_metrics(
    user_id: int,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    is_admin = _is_admin_role(current_user.role)
    if user_id != current_user.id and not is_admin:
        raise HTTPException(status_code=403, detail="Access denied")

    stmt = (
        select(TournamentPlayerMetricSnapshot)
        .where(TournamentPlayerMetricSnapshot.user_id == user_id)
        .order_by(TournamentPlayerMetricSnapshot.as_of.desc())
        .limit(1)
    )
    snapshot = (await db.execute(stmt)).scalar_one_or_none()
    if not snapshot:
        raise HTTPException(status_code=404, detail="No metric snapshot found")
    return {
        "user_id": user_id,
        "as_of": snapshot.as_of,
        "rounds_used": snapshot.rounds_used,
        "avg_score": float(snapshot.avg_score),
        "gir_pct": float(snapshot.gir_pct),
        "fairways_hit_pct": float(snapshot.fairways_hit_pct),
        "putts_per_round": float(snapshot.putts_per_round),
        "std_dev_score": float(snapshot.std_dev_score),
        "recent_form_score": float(snapshot.recent_form_score),
        "confidence_score": float(snapshot.confidence_score),
    }


@router.get("/me/metrics")
async def get_my_metrics(
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    return await get_player_metrics(current_user.id, current_user, db)


@router.get("/players/{user_id}/rating")
async def get_player_rating(
    user_id: int,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    is_admin = _is_admin_role(current_user.role)
    if user_id != current_user.id and not is_admin:
        raise HTTPException(status_code=403, detail="Access denied")

    stmt = (
        select(TournamentPlayerRating)
        .where(TournamentPlayerRating.user_id == user_id)
        .order_by(TournamentPlayerRating.as_of.desc())
        .limit(1)
    )
    rating = (await db.execute(stmt)).scalar_one_or_none()
    if not rating:
        raise HTTPException(status_code=404, detail="No rating found")
    return {
        "user_id": user_id,
        "as_of": rating.as_of,
        "rating_score": float(rating.rating_score),
        "confidence_score": float(rating.confidence_score),
        "formula_version": rating.rating_formula_version,
    }


@router.get("/me/rating")
async def get_my_rating(
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    return await get_player_rating(current_user.id, current_user, db)


@router.get("/players/{user_id}/trust-score")
async def get_trust_score(
    user_id: int,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    is_admin = _is_admin_role(current_user.role)
    if user_id != current_user.id and not is_admin:
        raise HTTPException(status_code=403, detail="Access denied")
    score = await upsert_trust_score(db, user_id)
    await db.commit()
    return {"user_id": user_id, "trust_score": round(score, 2)}


@router.get("/me/trust-score")
async def get_my_trust_score(
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    return await get_trust_score(current_user.id, current_user, db)


@router.get("/fraud-flags")
async def list_fraud_flags(
    status_filter: str | None = Query(default=None, alias="status"),
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = select(TournamentFraudFlag).order_by(TournamentFraudFlag.created_at.desc())
    if status_filter:
        stmt = stmt.where(TournamentFraudFlag.status == status_filter)
    flags = (await db.execute(stmt)).scalars().all()
    return {
        "flags": [
            {
                "id": f.id,
                "user_id": f.user_id,
                "round_id": f.round_id,
                "flag_type": f.flag_type,
                "severity": f.severity,
                "status": f.status,
                "details": f.details,
                "created_at": f.created_at,
            }
            for f in flags
        ]
    }


@router.post("/team-draw/generate")
async def generate_team_draw(
    payload: TeamDrawGenerateRequest,
    current_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    if len(payload.user_ids) < payload.team_size:
        raise HTTPException(status_code=400, detail="Not enough players for one full team")
    if payload.algorithm != "balanced_sum":
        raise HTTPException(status_code=400, detail="V1 currently supports balanced_sum only")

    players: list[dict[str, Any]] = []
    for user_id in payload.user_ids:
        rating_stmt = (
            select(TournamentPlayerRating)
            .where(TournamentPlayerRating.user_id == user_id)
            .order_by(TournamentPlayerRating.as_of.desc())
            .limit(1)
        )
        latest_rating = (await db.execute(rating_stmt)).scalar_one_or_none()
        if not latest_rating:
            raise HTTPException(status_code=400, detail=f"Missing rating for user {user_id}")

        profile_stmt = select(TournamentPlayerProfile).where(TournamentPlayerProfile.user_id == user_id)
        profile = (await db.execute(profile_stmt)).scalar_one_or_none()
        players.append(
            {
                "user_id": user_id,
                "rating": float(latest_rating.rating_score),
                "trust_score": float(profile.trust_score) if profile else 50.0,
            }
        )

    teams = _balanced_sum_teams(players, payload.team_size)
    team_totals = [sum(p["rating"] for p in team) for team in teams]
    balance_score = max(team_totals) - min(team_totals) if team_totals else 0.0

    draw_run = TournamentTeamDrawRun(
        event_key=payload.event_key,
        algorithm="balanced_sum",
        constraints_json={"team_size": payload.team_size},
        created_by=current_user.id,
        balance_score=Decimal(str(round(balance_score, 2))),
    )
    db.add(draw_run)
    await db.flush()

    for idx, team in enumerate(teams):
        label = f"Team {idx + 1}"
        for player in team:
            db.add(
                TournamentTeamAssignment(
                    draw_run_id=draw_run.id,
                    team_label=label,
                    user_id=player["user_id"],
                    player_rating=Decimal(str(round(player["rating"], 2))),
                    trust_score=Decimal(str(round(player["trust_score"], 2))),
                )
            )
    await db.commit()

    return {
        "draw_run_id": draw_run.id,
        "algorithm": draw_run.algorithm,
        "balance_score": float(draw_run.balance_score),
        "teams": [
            {
                "team_label": f"Team {idx + 1}",
                "total_rating": round(sum(p["rating"] for p in team), 2),
                "players": team,
            }
            for idx, team in enumerate(teams)
        ],
    }


@router.get("/team-draw/{run_id}")
async def get_team_draw(
    run_id: str,
    current_user: User = Depends(require_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    draw_stmt = select(TournamentTeamDrawRun).where(TournamentTeamDrawRun.id == run_id)
    draw_run = (await db.execute(draw_stmt)).scalar_one_or_none()
    if not draw_run:
        raise HTTPException(status_code=404, detail="Draw run not found")

    assignments_stmt = (
        select(TournamentTeamAssignment)
        .where(TournamentTeamAssignment.draw_run_id == run_id)
        .order_by(TournamentTeamAssignment.team_label.asc(), TournamentTeamAssignment.player_rating.desc())
    )
    assignments = (await db.execute(assignments_stmt)).scalars().all()

    teams: dict[str, list[dict[str, Any]]] = {}
    for a in assignments:
        teams.setdefault(a.team_label, []).append(
            {
                "user_id": a.user_id,
                "player_rating": float(a.player_rating),
                "trust_score": float(a.trust_score),
            }
        )

    return {
        "draw_run_id": draw_run.id,
        "event_key": draw_run.event_key,
        "algorithm": draw_run.algorithm,
        "balance_score": float(draw_run.balance_score),
        "created_at": draw_run.created_at,
        "teams": [
            {
                "team_label": label,
                "total_rating": round(sum(p["player_rating"] for p in players), 2),
                "players": players,
            }
            for label, players in teams.items()
        ],
    }
