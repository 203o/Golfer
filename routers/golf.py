from __future__ import annotations

import random
import re
import math
import secrets
import os
from datetime import date, datetime, timezone, timedelta
from decimal import Decimal
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from firebase_admin import auth as firebase_auth
from pydantic import BaseModel, Field, HttpUrl
from sqlalchemy import and_, delete, func, or_, select, text
from sqlalchemy.exc import IntegrityError, ProgrammingError
from sqlalchemy.ext.asyncio import AsyncSession

from auth_utils import firebase_app  # Ensure Firebase Admin SDK is initialized
from database import get_db
from dependencies import get_current_user, require_admin
from models_core import Transaction, User, Wallet, WalletLedger
from models_golf import (
    GolfCharity,
    GolfCharityDonation,
    GolfDraw,
    GolfDrawSettings,
    GolfDrawEntry,
    GolfPoolLedger,
    GolfPrizeRollover,
    GolfReferral,
    GolfReferralCode,
    GolfScore,
    GolfSubscription,
    GolfSubscriptionPayment,
    GolfSubscriptionPlan,
    GolfUserCharitySetting,
    GolfWinnerClaim,
    TournamentChallengeParticipant,
    TournamentChallengeSession,
    TournamentEvent,
    TournamentEventDonation,
    TournamentEventUnlock,
    TournamentFraudFlag,
    TournamentFriendRequest,
    TournamentInboxMessage,
    TournamentSessionScore,
)

router = APIRouter(prefix="/api/golf", tags=["Golf"])

POOL_CONTRIBUTION_BPS = 3000  # 30%
MATCH_5_SHARE_BPS = 4000
MATCH_4_SHARE_BPS = 3500
MATCH_3_SHARE_BPS = 2500
YEARLY_SUBSCRIPTION_MONTHS = 12
DEFAULT_WEEKLY_DRAW_PRIZE_CENTS = 50000
DEFAULT_MONTHLY_JACKPOT_PRIZES_CENTS = [200000, 150000, 100000]
DEFAULT_MONTHLY_MIN_EVENTS_REQUIRED = 5
DONATION_HALF_LIFE_DAYS = 45.0
DRAW_ALGO_VERSION = "v1_multiplicative_fair"
REFERRAL_BONUS_USD = 20.0
MIN_CHARITY_CONTRIBUTION_PCT = Decimal("10.00")
SUBSCRIPTION_AMOUNT_CENTS_BY_PLAN: dict[str, int] = {
    "monthly": 999,
    "yearly": 4999,
}

def _charity_slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", str(value or "").strip().lower()).strip("-")


DEFAULT_CHARITY_SEED: list[dict[str, Any]] = [
    {
        "name": "American Red Cross",
        "description": "Disaster relief, emergency assistance, blood donation, and training services.",
        "cause": "Disaster Relief",
        "location": "United States",
        "website_url": "https://www.redcross.org/",
        "hero_image_url": "https://picsum.photos/seed/red-cross-golf/1200/720",
        "gallery_image_urls": [
            "https://picsum.photos/seed/red-cross-golf/1200/720",
            "https://picsum.photos/seed/red-cross-volunteers/1200/720",
            "https://picsum.photos/seed/red-cross-community/1200/720",
        ],
        "spotlight_text": "Help fund rapid-response relief while players rally their communities through golf days and fundraising rounds.",
        "is_featured": True,
        "upcoming_events": [
            {
                "title": "Spring Relief Golf Day",
                "event_date": "2026-05-16",
                "location": "Pebble Beach, California",
                "description": "Community four-ball fundraiser supporting emergency response kits and volunteer training.",
                "registration_url": "https://www.redcross.org/",
                "image_url": "https://picsum.photos/seed/red-cross-event/900/540",
            }
        ],
    },
    {
        "name": "Feeding America",
        "description": "The largest hunger-relief organization in the U.S., operating food banks nationwide.",
        "cause": "Hunger Relief",
        "location": "United States",
        "website_url": "https://www.feedingamerica.org/",
        "hero_image_url": "https://picsum.photos/seed/feeding-america-golf/1200/720",
        "gallery_image_urls": [
            "https://picsum.photos/seed/feeding-america-golf/1200/720",
            "https://picsum.photos/seed/feeding-america-team/1200/720",
        ],
        "spotlight_text": "Turn each subscription into meals for families by backing food-bank partners through the golf community.",
        "upcoming_events": [
            {
                "title": "Fairways for Food Security",
                "event_date": "2026-06-06",
                "location": "Dallas, Texas",
                "description": "Charity scramble and auction raising support for regional food banks.",
                "registration_url": "https://www.feedingamerica.org/",
                "image_url": "https://picsum.photos/seed/feeding-america-event/900/540",
            }
        ],
    },
    {
        "name": "St. Jude Children's Research Hospital",
        "description": "Focuses on treating and researching pediatric catastrophic diseases.",
        "cause": "Child Health",
        "location": "Memphis, Tennessee",
        "website_url": "https://www.stjude.org/",
        "hero_image_url": "https://picsum.photos/seed/st-jude-golf/1200/720",
        "gallery_image_urls": [
            "https://picsum.photos/seed/st-jude-golf/1200/720",
            "https://picsum.photos/seed/st-jude-care/1200/720",
        ],
        "spotlight_text": "Support treatment, travel, and family care through a cause players can champion all season.",
        "upcoming_events": [
            {
                "title": "Champions for Hope Invitational",
                "event_date": "2026-06-19",
                "location": "Memphis, Tennessee",
                "description": "Corporate and member teams play to fund family support services and pediatric research.",
                "registration_url": "https://www.stjude.org/",
                "image_url": "https://picsum.photos/seed/st-jude-event/900/540",
            }
        ],
    },
    {
        "name": "Habitat for Humanity",
        "description": "Builds and repairs homes for families in need.",
        "cause": "Housing",
        "location": "Global",
        "website_url": "https://www.habitat.org/",
        "hero_image_url": "https://picsum.photos/seed/habitat-golf/1200/720",
        "gallery_image_urls": [
            "https://picsum.photos/seed/habitat-golf/1200/720",
            "https://picsum.photos/seed/habitat-build/1200/720",
        ],
        "spotlight_text": "Pair club competitions with practical housing support that communities can feel quickly.",
        "upcoming_events": [
            {
                "title": "Build & Birdie Weekend",
                "event_date": "2026-05-30",
                "location": "Orlando, Florida",
                "description": "A Friday golf mixer followed by a volunteer build day for local Habitat families.",
                "registration_url": "https://www.habitat.org/",
                "image_url": "https://picsum.photos/seed/habitat-event/900/540",
            }
        ],
    },
    {
        "name": "Doctors Without Borders",
        "description": "Provides medical aid in conflict zones and disaster areas worldwide.",
        "cause": "Medical Relief",
        "location": "Global",
        "website_url": "https://www.doctorswithoutborders.org/",
        "hero_image_url": "https://picsum.photos/seed/msf-golf/1200/720",
        "gallery_image_urls": [
            "https://picsum.photos/seed/msf-golf/1200/720",
            "https://picsum.photos/seed/msf-relief/1200/720",
        ],
        "spotlight_text": "Support emergency medical response teams through monthly subscriptions and one-off gifts alike.",
        "upcoming_events": [
            {
                "title": "Global Care Charity Classic",
                "event_date": "2026-07-11",
                "location": "Scottsdale, Arizona",
                "description": "Fundraising golf day benefiting frontline medical missions and rapid deployment supplies.",
                "registration_url": "https://www.doctorswithoutborders.org/",
                "image_url": "https://picsum.photos/seed/msf-event/900/540",
            }
        ],
    },
    {
        "name": "The Salvation Army",
        "description": "Offers social services, disaster relief, and rehabilitation programs.",
        "cause": "Community Support",
        "location": "United States",
        "website_url": "https://www.salvationarmyusa.org/",
        "hero_image_url": "https://picsum.photos/seed/salvation-army-golf/1200/720",
        "gallery_image_urls": [
            "https://picsum.photos/seed/salvation-army-golf/1200/720",
            "https://picsum.photos/seed/salvation-army-community/1200/720",
        ],
        "spotlight_text": "Back shelters, youth programs, and practical local support through monthly golfer giving.",
    },
    {
        "name": "United Way Worldwide",
        "description": "Supports education, financial stability, and health initiatives.",
        "cause": "Community Support",
        "location": "Global",
        "website_url": "https://www.unitedway.org/",
        "hero_image_url": "https://picsum.photos/seed/united-way-golf/1200/720",
        "gallery_image_urls": [
            "https://picsum.photos/seed/united-way-golf/1200/720",
            "https://picsum.photos/seed/united-way-community/1200/720",
        ],
        "spotlight_text": "A broad-impact option for members who want their giving to strengthen local education, health, and family stability.",
    },
    {
        "name": "Charity: Water",
        "description": "Funds clean and safe drinking water projects globally.",
        "cause": "Clean Water",
        "location": "Global",
        "website_url": "https://www.charitywater.org/",
        "hero_image_url": "https://picsum.photos/seed/charity-water-golf/1200/720",
        "gallery_image_urls": [
            "https://picsum.photos/seed/charity-water-golf/1200/720",
            "https://picsum.photos/seed/charity-water-project/1200/720",
            "https://picsum.photos/seed/charity-water-community/1200/720",
        ],
        "spotlight_text": "This month's spotlight pairs every golfer signup with a clean-water mission that is easy to follow and share.",
        "is_featured": True,
        "upcoming_events": [
            {
                "title": "Blue Fairways Benefit",
                "event_date": "2026-05-23",
                "location": "San Diego, California",
                "description": "Sunrise shotgun fundraiser powering new clean-water infrastructure projects.",
                "registration_url": "https://www.charitywater.org/",
                "image_url": "https://picsum.photos/seed/charity-water-event/900/540",
            },
            {
                "title": "Water Works Golf Mixer",
                "event_date": "2026-06-27",
                "location": "Austin, Texas",
                "description": "Member networking round and storytelling evening with impact updates from field partners.",
                "registration_url": "https://www.charitywater.org/",
                "image_url": "https://picsum.photos/seed/charity-water-evening/900/540",
            },
        ],
    },
    {
        "name": "Direct Relief",
        "description": "Provides medical supplies and disaster response support.",
        "cause": "Medical Relief",
        "location": "Global",
        "website_url": "https://www.directrelief.org/",
        "hero_image_url": "https://picsum.photos/seed/direct-relief-golf/1200/720",
        "gallery_image_urls": [
            "https://picsum.photos/seed/direct-relief-golf/1200/720",
            "https://picsum.photos/seed/direct-relief-medical/1200/720",
        ],
        "spotlight_text": "A reliable option for members who want donations converted into practical medical support quickly.",
    },
    {
        "name": "World Wildlife Fund",
        "description": "Focuses on wildlife conservation and environmental sustainability.",
        "cause": "Conservation",
        "location": "Global",
        "website_url": "https://www.worldwildlife.org/",
        "hero_image_url": "https://picsum.photos/seed/wwf-golf/1200/720",
        "gallery_image_urls": [
            "https://picsum.photos/seed/wwf-golf/1200/720",
            "https://picsum.photos/seed/wwf-conservation/1200/720",
        ],
        "spotlight_text": "For members motivated by climate, habitat, and species protection, WWF gives the directory a strong conservation option.",
        "is_featured": True,
        "upcoming_events": [
            {
                "title": "Greener Fairways Open",
                "event_date": "2026-07-18",
                "location": "Seattle, Washington",
                "description": "Sustainability-themed golf fundraiser supporting habitat restoration and biodiversity protection.",
                "registration_url": "https://www.worldwildlife.org/",
                "image_url": "https://picsum.photos/seed/wwf-event/900/540",
            }
        ],
    },
]

DEFAULT_CHARITY_SEED_BY_SLUG: dict[str, dict[str, Any]] = {
    _charity_slug(row.get("slug") or row["name"]): row for row in DEFAULT_CHARITY_SEED
}


def _is_missing_relation_error(exc: Exception) -> bool:
    message = str(exc).lower()
    return (
        "undefinedtableerror" in message
        or "undefinedcolumn" in message
        or ("relation" in message and "does not exist" in message)
        or ("column" in message and "does not exist" in message)
    )


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def month_key_for(dt: datetime) -> str:
    return f"{dt.year:04d}-{dt.month:02d}"


def wallet_available_amount(wallet: Wallet) -> float:
    return float(wallet.available_balance or wallet.token_balance or 0.0)


def ensure_unique_numbers(base_numbers: list[int], min_num: int = 1, max_num: int = 50) -> list[int]:
    used: set[int] = set()
    out: list[int] = []
    span = (max_num - min_num) + 1
    for raw in base_numbers:
        candidate = raw
        while candidate in used:
            candidate = min_num + ((candidate - min_num + 1) % span)
        used.add(candidate)
        out.append(candidate)
    return out


def derive_pick_numbers(scores: list[int]) -> list[int]:
    if len(scores) != 5:
        raise ValueError("Exactly five scores are required to derive draw numbers")
    base: list[int] = []
    for idx, score in enumerate(scores):
        mapped = ((score * 7) + ((idx + 1) * 11)) % 50 + 1
        base.append(mapped)
    return ensure_unique_numbers(base)


def generate_draw_numbers(seed: str | None = None) -> list[int]:
    rng = random.Random(seed or f"golf-draw-{utcnow().isoformat()}")
    nums = rng.sample(list(range(1, 51)), 5)
    nums.sort()
    return nums


def _normalize_draw_numbers(raw_numbers: list[int] | None) -> list[int]:
    if raw_numbers is None:
        raise HTTPException(status_code=422, detail="Five draw numbers are required")
    cleaned: list[int] = []
    for raw in raw_numbers:
        try:
            value = int(raw)
        except Exception as exc:
            raise HTTPException(status_code=422, detail="Draw numbers must be integers") from exc
        if value < 1 or value > 50:
            raise HTTPException(status_code=422, detail="Draw numbers must be between 1 and 50")
        cleaned.append(value)
    if len(cleaned) != 5:
        raise HTTPException(status_code=422, detail="Exactly five draw numbers are required")
    if len(set(cleaned)) != 5:
        raise HTTPException(status_code=422, detail="Draw numbers must be unique")
    return sorted(cleaned)


def _is_monthly_draw(month_key: str) -> bool:
    return "-W" not in str(month_key or "")


def _draw_logic_mode(value: str | None) -> str:
    normalized = (value or "random").strip().lower()
    if normalized not in {"random", "algorithmic"}:
        raise HTTPException(status_code=422, detail="Draw logic must be random or algorithmic")
    return normalized


def _entry_score_values(entry: GolfDrawEntry) -> list[int]:
    raw = entry.score_window
    if isinstance(raw, dict):
        values = raw.get("scores")
        if isinstance(values, list):
            return [int(v) for v in values if isinstance(v, (int, float))]
    if isinstance(raw, list):
        return [int(v) for v in raw if isinstance(v, (int, float))]
    return []


def _entry_pick_numbers(entry: GolfDrawEntry) -> list[int]:
    raw = entry.numbers if isinstance(entry.numbers, list) else []
    out: list[int] = []
    for value in raw:
        if isinstance(value, (int, float)):
            number = int(value)
            if 1 <= number <= 50:
                out.append(number)
    return sorted(set(out))


def _tier_key(match_count: int) -> str:
    return f"match_{int(match_count)}"


def _tier_label(match_count: int) -> str:
    if int(match_count) in {3, 4, 5}:
        return f"{int(match_count)}-Number Match"
    return "No Reward"


def _split_pool_cents(pool_cents: int, entry_ids: list[str]) -> dict[str, int]:
    if pool_cents <= 0 or not entry_ids:
        return {}
    ordered_ids = [str(entry_id) for entry_id in sorted(entry_ids)]
    base = int(pool_cents) // len(ordered_ids)
    remainder = int(pool_cents) % len(ordered_ids)
    payouts: dict[str, int] = {}
    for idx, entry_id in enumerate(ordered_ids):
        payouts[entry_id] = int(base + (1 if idx < remainder else 0))
    return payouts


def _share_pct(bps: int) -> float:
    return round(float(bps) / 100.0, 2)


def _normalize_string_list(raw: Any) -> list[str]:
    if not isinstance(raw, list):
        return []
    values: list[str] = []
    for item in raw:
        value = str(item or "").strip()
        if value:
            values.append(value)
    return values


def _normalize_charity_events(raw: Any) -> list[dict[str, Any]]:
    if not isinstance(raw, list):
        return []
    events: list[dict[str, Any]] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        title = str(item.get("title") or "").strip()
        if not title:
            continue
        event_date = str(item.get("event_date") or "").strip() or None
        location = str(item.get("location") or "").strip() or None
        description = str(item.get("description") or "").strip() or None
        registration_url = str(item.get("registration_url") or "").strip() or None
        image_url = str(item.get("image_url") or "").strip() or None
        events.append(
            {
                "title": title,
                "event_date": event_date,
                "location": location,
                "description": description,
                "registration_url": registration_url,
                "image_url": image_url,
            }
        )
    return events


def _serialize_charity_event_inputs(raw_events: list[Any] | None) -> list[dict[str, Any]] | None:
    if not raw_events:
        return None
    events: list[dict[str, Any]] = []
    for item in raw_events:
        if isinstance(item, CharityEventInput):
            events.append(
                {
                    "title": item.title.strip(),
                    "event_date": item.event_date.isoformat() if item.event_date else None,
                    "location": (item.location or "").strip() or None,
                    "description": (item.description or "").strip() or None,
                    "registration_url": str(item.registration_url) if item.registration_url else None,
                    "image_url": str(item.image_url) if item.image_url else None,
                }
            )
            continue
        if isinstance(item, dict):
            normalized = _normalize_charity_events([item])
            if normalized:
                events.extend(normalized)
    return events or None


def _charity_defaults(*, slug: str | None = None, name: str | None = None) -> dict[str, Any]:
    key = _charity_slug(slug or name or "")
    return DEFAULT_CHARITY_SEED_BY_SLUG.get(key, {})


def _serialize_charity(charity: GolfCharity) -> dict[str, Any]:
    defaults = _charity_defaults(slug=charity.slug, name=charity.name)
    description = (charity.description or defaults.get("description") or "").strip() or None
    cause = (getattr(charity, "cause", None) or defaults.get("cause") or "Community Impact").strip()
    location = (getattr(charity, "location", None) or defaults.get("location") or "").strip() or None
    website_url = (charity.website_url or defaults.get("website_url") or "").strip() or None
    hero_image_url = (
        getattr(charity, "hero_image_url", None) or defaults.get("hero_image_url") or ""
    ).strip() or None
    gallery_image_urls = _normalize_string_list(getattr(charity, "gallery_image_urls", None))
    if not gallery_image_urls:
        gallery_image_urls = _normalize_string_list(defaults.get("gallery_image_urls"))
    if hero_image_url and hero_image_url not in gallery_image_urls:
        gallery_image_urls.insert(0, hero_image_url)
    upcoming_events = _normalize_charity_events(getattr(charity, "upcoming_events", None))
    if not upcoming_events:
        upcoming_events = _normalize_charity_events(defaults.get("upcoming_events"))
    spotlight_text = (
        getattr(charity, "spotlight_text", None) or defaults.get("spotlight_text") or ""
    ).strip() or None
    is_featured = bool(getattr(charity, "is_featured", False) or defaults.get("is_featured"))
    return {
        "id": charity.id,
        "name": charity.name,
        "slug": charity.slug,
        "description": description,
        "cause": cause,
        "location": location,
        "website_url": website_url,
        "hero_image_url": hero_image_url,
        "gallery_image_urls": gallery_image_urls,
        "upcoming_events": upcoming_events,
        "spotlight_text": spotlight_text,
        "is_featured": is_featured,
        "total_raised_cents": int(charity.total_raised_cents or 0),
    }


def _charity_matches_filters(
    charity: dict[str, Any],
    *,
    search: str | None = None,
    cause: str | None = None,
    featured_only: bool = False,
) -> bool:
    if featured_only and charity.get("is_featured") is not True:
        return False
    cause_filter = (cause or "").strip().lower()
    if cause_filter and (charity.get("cause") or "").strip().lower() != cause_filter:
        return False
    search_value = (search or "").strip().lower()
    if not search_value:
        return True
    haystack = " ".join(
        [
            str(charity.get("name") or ""),
            str(charity.get("description") or ""),
            str(charity.get("cause") or ""),
            str(charity.get("location") or ""),
            str(charity.get("spotlight_text") or ""),
            " ".join(
                str(event.get("title") or "")
                for event in (charity.get("upcoming_events") or [])
                if isinstance(event, dict)
            ),
        ]
    ).lower()
    return search_value in haystack


async def _active_charity_by_ref(
    db: AsyncSession,
    charity_ref: str,
    *,
    active_only: bool = True,
) -> GolfCharity | None:
    raw_value = str(charity_ref or "").strip()
    if not raw_value:
        return None
    stmt = select(GolfCharity).where(
        or_(
            GolfCharity.id == raw_value,
            GolfCharity.slug == _charity_slug(raw_value),
        )
    )
    if active_only:
        stmt = stmt.where(GolfCharity.is_active.is_(True))
    return (await db.execute(stmt.limit(1))).scalar_one_or_none()


def _plan_monthly_equivalent_cents(plan_id: str) -> int:
    normalized = str(plan_id or "").strip().lower()
    amount_cents = int(SUBSCRIPTION_AMOUNT_CENTS_BY_PLAN.get(normalized, 0))
    if normalized == "yearly":
        return int(round(amount_cents / YEARLY_SUBSCRIPTION_MONTHS))
    return amount_cents


def _subscription_contribution_cents_for_plan(plan_id: str) -> int:
    monthly_equivalent_cents = _plan_monthly_equivalent_cents(plan_id)
    return int(round(monthly_equivalent_cents * POOL_CONTRIBUTION_BPS / 10000.0))


def _base_pool_tier_amounts(base_pool_total_cents: int) -> dict[int, int]:
    total = max(int(base_pool_total_cents or 0), 0)
    match5_base = int(total * MATCH_5_SHARE_BPS / 10000)
    match4_pool = int(total * MATCH_4_SHARE_BPS / 10000)
    match3_pool = max(total - match5_base - match4_pool, 0)
    return {
        5: match5_base,
        4: match4_pool,
        3: match3_pool,
    }


def _prize_pool_breakdown(
    *,
    base_pool_total_cents: int,
    jackpot_carry_in_cents: int,
) -> dict[str, Any]:
    base_tiers = _base_pool_tier_amounts(base_pool_total_cents)
    match5_base = int(base_tiers[5])
    match4_pool = int(base_tiers[4])
    match3_pool = int(base_tiers[3])
    carry_in = max(int(jackpot_carry_in_cents or 0), 0)
    match5_total = int(match5_base + carry_in)
    return {
        "subscription_contribution_bps": int(POOL_CONTRIBUTION_BPS),
        "subscription_contribution_pct": _share_pct(POOL_CONTRIBUTION_BPS),
        "base_pool_total_cents": int(base_pool_total_cents or 0),
        "pool_total_cents": int(base_pool_total_cents or 0),
        "jackpot_carry_in_cents": carry_in,
        "total_prize_exposure_cents": int(base_pool_total_cents or 0) + carry_in,
        "tier_shares_bps": {
            "match_5": MATCH_5_SHARE_BPS,
            "match_4": MATCH_4_SHARE_BPS,
            "match_3": MATCH_3_SHARE_BPS,
        },
        "tier_summary": {
            "match_5": {
                "label": "5-Number Match",
                "share_bps": MATCH_5_SHARE_BPS,
                "share_pct": _share_pct(MATCH_5_SHARE_BPS),
                "base_pool_cents": match5_base,
                "pool_cents": match5_total,
                "rollover": True,
            },
            "match_4": {
                "label": "4-Number Match",
                "share_bps": MATCH_4_SHARE_BPS,
                "share_pct": _share_pct(MATCH_4_SHARE_BPS),
                "base_pool_cents": match4_pool,
                "pool_cents": match4_pool,
                "rollover": False,
            },
            "match_3": {
                "label": "3-Number Match",
                "share_bps": MATCH_3_SHARE_BPS,
                "share_pct": _share_pct(MATCH_3_SHARE_BPS),
                "base_pool_cents": match3_pool,
                "pool_cents": match3_pool,
                "rollover": False,
            },
        },
    }


async def _active_subscription_pool_snapshot(
    db: AsyncSession,
    *,
    as_of: datetime,
    jackpot_carry_in_cents: int = 0,
) -> dict[str, Any]:
    active_subs_stmt = (
        select(
            GolfSubscription.plan_id,
            func.count(func.distinct(GolfSubscription.user_id)),
        )
        .where(
            GolfSubscription.status == "active",
            GolfSubscription.current_period_start <= as_of,
            GolfSubscription.current_period_end >= as_of,
        )
        .group_by(GolfSubscription.plan_id)
    )
    rows = (await db.execute(active_subs_stmt)).all()

    plan_breakdown: list[dict[str, Any]] = []
    active_subscriber_count = 0
    base_pool_total_cents = 0
    for raw_plan_id, raw_count in rows:
        plan_id = str(raw_plan_id or "").strip().lower()
        subscriber_count = int(raw_count or 0)
        per_active_contribution_cents = _subscription_contribution_cents_for_plan(plan_id)
        plan_total_cents = int(per_active_contribution_cents * subscriber_count)
        active_subscriber_count += subscriber_count
        base_pool_total_cents += plan_total_cents
        plan_breakdown.append(
            {
                "plan_id": plan_id or "unknown",
                "subscriber_count": subscriber_count,
                "monthly_equivalent_cents": _plan_monthly_equivalent_cents(plan_id),
                "per_active_contribution_cents": per_active_contribution_cents,
                "pool_contribution_cents": plan_total_cents,
            }
        )

    pool_breakdown = _prize_pool_breakdown(
        base_pool_total_cents=base_pool_total_cents,
        jackpot_carry_in_cents=jackpot_carry_in_cents,
    )
    return {
        **pool_breakdown,
        "active_subscriber_count": active_subscriber_count,
        "plan_breakdown": plan_breakdown,
        "snapshot_at": as_of.isoformat(),
    }


def _weighted_number_sample(
    weights: dict[int, float],
    *,
    k: int,
    seed: str,
) -> list[int]:
    rng = random.Random(seed)
    available = sorted(int(number) for number in weights.keys())
    picked: list[int] = []
    while available and len(picked) < k:
        total = sum(max(float(weights.get(number, 0.0)), 1e-6) for number in available)
        roll = rng.random() * total
        upto = 0.0
        chosen = available[-1]
        for number in available:
            upto += max(float(weights.get(number, 0.0)), 1e-6)
            if upto >= roll:
                chosen = number
                break
        picked.append(int(chosen))
        available.remove(chosen)
    picked.sort()
    return picked


def _build_algorithmic_number_plan(entries: list[GolfDrawEntry], *, seed: str) -> dict[str, Any]:
    frequencies = {number: 0 for number in range(1, 51)}
    for entry in entries:
        for number in _entry_pick_numbers(entry):
            frequencies[number] = int(frequencies.get(number, 0) + 1)

    max_count = max(frequencies.values()) if frequencies else 0
    nonzero_counts = [count for count in frequencies.values() if count > 0]
    min_nonzero = min(nonzero_counts) if nonzero_counts else 1

    weights: dict[int, float] = {}
    for number, count in frequencies.items():
        if max_count <= 0:
            weights[number] = 1.0
            continue
        popularity = float(count) / float(max_count)
        rarity = 1.0 if count == 0 else min(1.0, float(min_nonzero) / float(count))
        extremity = max(popularity, rarity)
        weights[number] = round(1.0 + (extremity ** 1.35) * 1.8 + (0.15 if count == 0 else 0.0), 6)

    hot_numbers = [
        {"number": number, "frequency": int(count)}
        for number, count in sorted(frequencies.items(), key=lambda item: (-item[1], item[0]))[:10]
    ]
    cold_numbers = [
        {"number": number, "frequency": int(count)}
        for number, count in sorted(frequencies.items(), key=lambda item: (item[1], item[0]))[:10]
    ]

    return {
        "numbers": _weighted_number_sample(weights, k=5, seed=seed),
        "frequency_map": {str(number): int(count) for number, count in frequencies.items()},
        "weight_map": {str(number): float(weight) for number, weight in weights.items()},
        "hot_numbers": hot_numbers,
        "cold_numbers": cold_numbers,
    }


def _evaluate_monthly_draw(
    *,
    draw: GolfDraw,
    entries: list[GolfDrawEntry],
    draw_numbers: list[int],
    logic_mode: str,
    pool_breakdown: dict[str, Any],
    seed: str,
    simulated_at: datetime,
) -> dict[str, Any]:
    normalized_numbers = _normalize_draw_numbers(draw_numbers)
    pool_tiers = (
        pool_breakdown.get("tier_summary")
        if isinstance(pool_breakdown.get("tier_summary"), dict)
        else {}
    )
    match5_pool = int(((pool_tiers.get("match_5") or {}).get("pool_cents")) or 0)
    match4_pool = int(((pool_tiers.get("match_4") or {}).get("pool_cents")) or 0)
    match3_pool = int(((pool_tiers.get("match_3") or {}).get("pool_cents")) or 0)
    tier_pool_map = {
        5: match5_pool,
        4: match4_pool,
        3: match3_pool,
    }

    tier_entries: dict[int, list[dict[str, Any]]] = {5: [], 4: [], 3: []}
    entry_results: list[dict[str, Any]] = []
    draw_number_set = set(normalized_numbers)

    for entry in entries:
        entry_numbers = _entry_pick_numbers(entry)
        matched_numbers = sorted(draw_number_set.intersection(entry_numbers))
        match_count = len(matched_numbers)
        result = {
            "entry_id": entry.id,
            "user_id": int(entry.user_id),
            "entry_numbers": entry_numbers,
            "score_values": _entry_score_values(entry),
            "matched_numbers": matched_numbers,
            "match_count": int(match_count),
            "tier_label": _tier_label(match_count),
            "is_winner": bool(match_count >= 3),
            "payout_cents": 0,
        }
        entry_results.append(result)
        if match_count in tier_entries:
            tier_entries[match_count].append(result)

    payout_allocations: dict[str, int] = {}
    tier_summary: dict[str, Any] = {}
    for match_count in (5, 4, 3):
        pool_cents = int(tier_pool_map[match_count])
        winners = tier_entries[match_count]
        per_entry = _split_pool_cents(pool_cents, [str(item["entry_id"]) for item in winners])
        total_awarded_cents = int(sum(per_entry.values()))
        for result in winners:
            payout = int(per_entry.get(str(result["entry_id"]), 0))
            result["payout_cents"] = payout
            payout_allocations[str(result["entry_id"])] = payout
        tier_summary[_tier_key(match_count)] = {
            "label": _tier_label(match_count),
            "winner_count": len(winners),
            "share_bps": int(((pool_tiers.get(_tier_key(match_count)) or {}).get("share_bps")) or 0),
            "pool_cents": pool_cents,
            "awarded_cents": total_awarded_cents,
        }

    rollover_cents = int(match5_pool) if not tier_entries[5] else 0
    total_awarded_cents = int(sum(item["payout_cents"] for item in entry_results))
    winner_count = sum(1 for item in entry_results if item["is_winner"])

    return {
        "logic_mode": logic_mode,
        "seed": seed,
        "numbers": normalized_numbers,
        "entry_count": len(entries),
        "winner_count": winner_count,
        "simulated_at": simulated_at,
        "tier_summary": tier_summary,
        "entry_results": entry_results,
        "rollover_cents": rollover_cents,
        "jackpot_won": bool(tier_entries[5]),
        "pool_total_cents": int(pool_breakdown.get("pool_total_cents") or 0),
        "total_prize_exposure_cents": int(pool_breakdown.get("total_prize_exposure_cents") or 0),
        "total_awarded_cents": total_awarded_cents,
    }


def _serialize_draw_preview(raw: dict[str, Any] | None) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    summary = raw.get("tier_summary") if isinstance(raw.get("tier_summary"), dict) else {}
    raw_numbers = raw.get("numbers")
    numbers: list[int] = []
    if isinstance(raw_numbers, list):
        try:
            numbers = _normalize_draw_numbers(raw_numbers)
        except HTTPException:
            numbers = []
    return {
        "logic_mode": str(raw.get("logic_mode") or "random"),
        "numbers": numbers,
        "simulated_at": raw.get("simulated_at"),
        "published_at": raw.get("published_at"),
        "preview_only": bool(raw.get("preview_only", False)),
        "entry_count": int(raw.get("entry_count") or 0),
        "winner_count": int(raw.get("winner_count") or 0),
        "rollover_cents": int(raw.get("rollover_cents") or 0),
        "jackpot_won": bool(raw.get("jackpot_won")),
        "tier_summary": summary,
        "pool_breakdown": raw.get("pool_breakdown"),
        "frequency_analysis": raw.get("frequency_analysis"),
    }


def _is_admin_email(email: str | None) -> bool:
    value = (email or "").strip().lower()
    if not value:
        return False
    configured = os.getenv("ADMIN_EMAILS", "").strip()
    if not configured:
        # Security hardening: no implicit admin fallback.
        return False
    allow = {x.strip().lower() for x in configured.split(",") if x.strip()}
    return value in allow


def _normalize_referral_code(raw_code: str | None) -> str:
    value = (raw_code or "").strip().upper()
    return re.sub(r"[^A-Z0-9]", "", value)


def _request_origin(request: Request) -> str:
    origin = (request.headers.get("origin") or "").strip().rstrip("/")
    if origin.startswith("http://") or origin.startswith("https://"):
        return origin

    proto = (
        (request.headers.get("x-forwarded-proto") or "").split(",")[0].strip()
        or request.url.scheme
        or "http"
    )
    host = (
        (request.headers.get("x-forwarded-host") or "").split(",")[0].strip()
        or (request.headers.get("host") or "").split(",")[0].strip()
        or request.url.netloc
    )
    if host:
        return f"{proto}://{host}".rstrip("/")
    return "http://localhost:7488"


def _build_referral_link(request: Request, referral_code: str) -> str:
    base = _request_origin(request)
    return f"{base}/?ref={referral_code}"


def _generate_referral_code() -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    code = "".join(secrets.choice(alphabet) for _ in range(8))
    return f"GF{code}"


async def _ensure_referral_code_for_user(
    db: AsyncSession,
    user_id: int,
) -> GolfReferralCode:
    existing = (
        await db.execute(
            select(GolfReferralCode)
            .where(GolfReferralCode.user_id == user_id)
            .limit(1)
        )
    ).scalar_one_or_none()
    if existing:
        return existing

    for _ in range(16):
        candidate = _generate_referral_code()
        code_exists = (
            await db.execute(
                select(GolfReferralCode.id)
                .where(GolfReferralCode.code == candidate)
                .limit(1)
            )
        ).scalar_one_or_none()
        if code_exists:
            continue
        row = GolfReferralCode(user_id=user_id, code=candidate)
        db.add(row)
        await db.commit()
        await db.refresh(row)
        return row

    raise HTTPException(status_code=500, detail="Unable to create referral code")


async def _capture_referral_if_eligible(
    db: AsyncSession,
    *,
    referred_user: User,
    referral_code: str | None,
) -> tuple[bool, str]:
    normalized = _normalize_referral_code(referral_code)
    if not normalized:
        return False, "missing_referral_code"

    existing_referral = (
        await db.execute(
            select(GolfReferral)
            .where(GolfReferral.referred_user_id == referred_user.id)
            .limit(1)
        )
    ).scalar_one_or_none()
    if existing_referral:
        return False, "already_captured"

    owner_code = (
        await db.execute(
            select(GolfReferralCode)
            .where(GolfReferralCode.code == normalized)
            .limit(1)
        )
    ).scalar_one_or_none()
    if not owner_code:
        return False, "invalid_referral_code"
    if int(owner_code.user_id) == int(referred_user.id):
        return False, "self_referral_not_allowed"

    prior_payments_count = int(
        (
            await db.execute(
                select(func.count(GolfSubscriptionPayment.id)).where(
                    GolfSubscriptionPayment.user_id == referred_user.id
                )
            )
        ).scalar_one()
        or 0
    )
    if prior_payments_count > 0:
        return False, "ineligible_existing_paid_subscription"

    db.add(
        GolfReferral(
            referrer_user_id=owner_code.user_id,
            referred_user_id=referred_user.id,
            referral_code=normalized,
            status="captured",
            reward_amount_usd=Decimal(str(REFERRAL_BONUS_USD)),
        )
    )
    return True, "captured"


def _draw_kind_from_key(month_key: str) -> str:
    return "weekly" if "-W" in month_key else "monthly_jackpot"


def _draw_key_for(kind: str, dt: datetime) -> str:
    if kind == "weekly":
        iso = dt.isocalendar()
        return f"{iso.year}-W{iso.week:02d}"
    return month_key_for(dt)


def _month_window(dt: datetime) -> tuple[datetime, datetime]:
    start = datetime(dt.year, dt.month, 1, tzinfo=timezone.utc)
    if dt.month == 12:
        end = datetime(dt.year + 1, 1, 1, tzinfo=timezone.utc)
    else:
        end = datetime(dt.year, dt.month + 1, 1, tzinfo=timezone.utc)
    return start, end


def _default_draw_settings_payload() -> dict[str, int]:
    return {
        "weekly_prize_cents": int(DEFAULT_WEEKLY_DRAW_PRIZE_CENTS),
        "monthly_first_prize_cents": int(DEFAULT_MONTHLY_JACKPOT_PRIZES_CENTS[0]),
        "monthly_second_prize_cents": int(DEFAULT_MONTHLY_JACKPOT_PRIZES_CENTS[1]),
        "monthly_third_prize_cents": int(DEFAULT_MONTHLY_JACKPOT_PRIZES_CENTS[2]),
        "monthly_min_events_required": int(DEFAULT_MONTHLY_MIN_EVENTS_REQUIRED),
    }


async def _ensure_draw_settings_schema(db: AsyncSession) -> None:
    await db.execute(
        text(
            """
            CREATE TABLE IF NOT EXISTS golf_draw_settings (
                id INTEGER PRIMARY KEY,
                weekly_prize_cents BIGINT NOT NULL DEFAULT 50000,
                monthly_first_prize_cents BIGINT NOT NULL DEFAULT 200000,
                monthly_second_prize_cents BIGINT NOT NULL DEFAULT 150000,
                monthly_third_prize_cents BIGINT NOT NULL DEFAULT 100000,
                monthly_min_events_required INTEGER NOT NULL DEFAULT 5,
                updated_by INTEGER NULL,
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
            """
        )
    )


def _serialize_draw_settings(row: GolfDrawSettings) -> dict[str, Any]:
    return {
        "weekly_prize_cents": int(row.weekly_prize_cents or 0),
        "monthly_first_prize_cents": int(row.monthly_first_prize_cents or 0),
        "monthly_second_prize_cents": int(row.monthly_second_prize_cents or 0),
        "monthly_third_prize_cents": int(row.monthly_third_prize_cents or 0),
        "monthly_min_events_required": int(row.monthly_min_events_required or 1),
        "subscription_contribution_bps": int(POOL_CONTRIBUTION_BPS),
        "subscription_contribution_pct": _share_pct(POOL_CONTRIBUTION_BPS),
        "tier_shares_bps": {
            "match_5": MATCH_5_SHARE_BPS,
            "match_4": MATCH_4_SHARE_BPS,
            "match_3": MATCH_3_SHARE_BPS,
        },
        "updated_by": row.updated_by,
        "updated_at": row.updated_at,
    }


async def _get_or_create_draw_settings(db: AsyncSession) -> GolfDrawSettings:
    await _ensure_draw_settings_schema(db)
    row = (
        await db.execute(
            select(GolfDrawSettings)
            .where(GolfDrawSettings.id == 1)
            .limit(1)
        )
    ).scalar_one_or_none()
    if row:
        return row

    defaults = _default_draw_settings_payload()
    row = GolfDrawSettings(
        id=1,
        weekly_prize_cents=defaults["weekly_prize_cents"],
        monthly_first_prize_cents=defaults["monthly_first_prize_cents"],
        monthly_second_prize_cents=defaults["monthly_second_prize_cents"],
        monthly_third_prize_cents=defaults["monthly_third_prize_cents"],
        monthly_min_events_required=defaults["monthly_min_events_required"],
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return row


def _validate_draw_settings_values(
    *,
    weekly_prize_cents: int,
    monthly_first_prize_cents: int,
    monthly_second_prize_cents: int,
    monthly_third_prize_cents: int,
    monthly_min_events_required: int,
) -> None:
    if weekly_prize_cents < 0:
        raise HTTPException(status_code=422, detail="Weekly prize must be non-negative")
    if min(
        monthly_first_prize_cents,
        monthly_second_prize_cents,
        monthly_third_prize_cents,
    ) < 0:
        raise HTTPException(status_code=422, detail="Monthly prizes must be non-negative")
    if monthly_first_prize_cents < monthly_second_prize_cents or monthly_second_prize_cents < monthly_third_prize_cents:
        raise HTTPException(
            status_code=422,
            detail="Monthly prizes must follow First >= Second >= Third",
        )
    if monthly_min_events_required < 1:
        raise HTTPException(
            status_code=422,
            detail="Minimum draw entries must be at least 1",
        )


def _median(values: list[float]) -> float:
    if not values:
        return 0.0
    sorted_vals = sorted(values)
    n = len(sorted_vals)
    mid = n // 2
    if n % 2 == 1:
        return float(sorted_vals[mid])
    return float((sorted_vals[mid - 1] + sorted_vals[mid]) / 2.0)


def _percentile(values: list[float], q: float) -> float:
    if not values:
        return 0.0
    sorted_vals = sorted(values)
    idx = max(0, min(len(sorted_vals) - 1, int(round((len(sorted_vals) - 1) * q))))
    return float(sorted_vals[idx])


def _normalize_nonnegative(value: float, max_value: float) -> float:
    if max_value <= 0:
        return 0.0
    return max(0.0, min(1.0, value / max_value))


def _weighted_sample_without_replacement(items: list[dict[str, Any]], k: int) -> list[dict[str, Any]]:
    if not items or k <= 0:
        return []
    sys_rng = secrets.SystemRandom()
    keyed: list[tuple[float, dict[str, Any]]] = []
    for item in items:
        w = max(float(item.get("final_weight", 0.0)), 1e-9)
        u = max(sys_rng.random(), 1e-12)
        # Efraimidis-Spirakis key.
        key = u ** (1.0 / w)
        keyed.append((key, item))
    keyed.sort(key=lambda x: x[0], reverse=True)
    return [x[1] for x in keyed[:k]]


def _status_count_map(rows: list[tuple[Any, Any]]) -> dict[str, int]:
    out: dict[str, int] = {}
    for key, count in rows:
        out[str(key)] = int(count or 0)
    return out


def _dense_daily_series(
    start_day: date,
    days: int,
    rows: list[tuple[Any, Any]],
) -> list[dict[str, Any]]:
    bucket: dict[str, int] = {}
    for raw_day, raw_value in rows:
        if isinstance(raw_day, datetime):
            day_key = raw_day.date().isoformat()
        elif isinstance(raw_day, date):
            day_key = raw_day.isoformat()
        else:
            day_key = str(raw_day)
        bucket[day_key] = int(raw_value or 0)
    return [
        {"day": (start_day + timedelta(days=i)).isoformat(), "value": int(bucket.get((start_day + timedelta(days=i)).isoformat(), 0))}
        for i in range(days)
    ]


async def _build_fair_draw_candidates(
    db: AsyncSession,
    *,
    kind: str,
    cutoff: datetime,
    monthly_min_events_required: int = DEFAULT_MONTHLY_MIN_EVENTS_REQUIRED,
) -> list[dict[str, Any]]:
    # Subscribers active at cutoff are the only candidates.
    subscribers_stmt = (
        select(User.id, User.username)
        .join(GolfSubscription, GolfSubscription.user_id == User.id)
        .where(
            GolfSubscription.status == "active",
            GolfSubscription.current_period_end >= cutoff,
            GolfSubscription.current_period_start <= cutoff,
            User.role == "subscriber",
        )
        .group_by(User.id, User.username)
    )
    subscriber_rows = (await db.execute(subscribers_stmt)).all()
    if not subscriber_rows:
        return []
    user_ids = [int(r[0]) for r in subscriber_rows]
    username_by_user = {int(r[0]): r[1] for r in subscriber_rows}

    perf_stmt = (
        select(
            TournamentSessionScore.player_user_id,
            func.coalesce(func.sum(TournamentSessionScore.total_score), 0),
            func.coalesce(func.stddev_pop(TournamentSessionScore.total_score), 0.0),
        )
        .where(
            TournamentSessionScore.player_user_id.in_(user_ids),
            TournamentSessionScore.status == "confirmed",
            TournamentSessionScore.reviewed_at <= cutoff,
        )
        .group_by(TournamentSessionScore.player_user_id)
    )
    perf_rows = (await db.execute(perf_stmt)).all()
    perf_by_user = {int(r[0]): float(r[1] or 0.0) for r in perf_rows}
    std_by_user = {int(r[0]): float(r[2] or 0.0) for r in perf_rows}

    # Donation with time decay (diminishing old donations influence).
    donation_stmt = (
        select(GolfCharityDonation.user_id, GolfCharityDonation.amount_cents, GolfCharityDonation.created_at)
        .where(
            GolfCharityDonation.user_id.in_(user_ids),
            GolfCharityDonation.created_at <= cutoff,
        )
    )
    donation_rows = (await db.execute(donation_stmt)).all()
    decay_lambda = math.log(2.0) / DONATION_HALF_LIFE_DAYS
    donation_effective_by_user: dict[int, float] = {uid: 0.0 for uid in user_ids}
    for uid, amount_cents, created_at in donation_rows:
        age_days = max(0.0, (cutoff - created_at).total_seconds() / 86400.0) if created_at else 0.0
        decay = math.exp(-decay_lambda * age_days)
        donation_effective_by_user[int(uid)] += float(amount_cents or 0.0) * decay

    # Activity and jackpot eligibility: completed distinct events in month.
    if kind == "monthly_jackpot":
        window_start, window_end = _month_window(cutoff)
    else:
        window_start = cutoff - timedelta(days=30)
        window_end = cutoff

    activity_stmt = (
        select(
            TournamentChallengeParticipant.user_id,
            func.count(func.distinct(TournamentChallengeSession.event_id)),
        )
        .join(
            TournamentChallengeSession,
            TournamentChallengeSession.id == TournamentChallengeParticipant.session_id,
        )
        .where(
            TournamentChallengeParticipant.user_id.in_(user_ids),
            TournamentChallengeParticipant.invite_state == "accepted",
            TournamentChallengeSession.status.in_(["completed", "auto_closed"]),
            TournamentChallengeSession.completed_at >= window_start,
            TournamentChallengeSession.completed_at < window_end,
        )
        .group_by(TournamentChallengeParticipant.user_id)
    )
    activity_rows = (await db.execute(activity_stmt)).all()
    activity_by_user = {int(r[0]): int(r[1] or 0) for r in activity_rows}

    base_candidates: list[dict[str, Any]] = []
    for user_id in user_ids:
        completed_events = int(activity_by_user.get(user_id, 0))
        if kind == "monthly_jackpot" and completed_events < int(monthly_min_events_required):
            continue
        perf_value = float(perf_by_user.get(user_id, 0.0))
        std_value = float(std_by_user.get(user_id, 0.0))
        consistency_raw = 1.0 / (1.0 + max(0.0, std_value))
        donation_effective = float(donation_effective_by_user.get(user_id, 0.0))
        base_candidates.append(
            {
                "user_id": user_id,
                "username": username_by_user.get(user_id, f"user{user_id}"),
                "performance_raw": perf_value,
                "consistency_raw": consistency_raw,
                "donation_effective_cents": donation_effective,
                "completed_events": completed_events,
            }
        )

    if not base_candidates:
        return []

    max_perf = max((c["performance_raw"] for c in base_candidates), default=0.0)
    max_consistency = max((c["consistency_raw"] for c in base_candidates), default=0.0)
    max_donation = max((c["donation_effective_cents"] for c in base_candidates), default=0.0)
    max_activity = max((float(c["completed_events"]) for c in base_candidates), default=0.0)

    for c in base_candidates:
        perf_norm = _normalize_nonnegative(float(c["performance_raw"]), max_perf)
        consistency_norm = _normalize_nonnegative(float(c["consistency_raw"]), max_consistency)
        donation_norm = _normalize_nonnegative(float(c["donation_effective_cents"]), max_donation)
        activity_norm = _normalize_nonnegative(float(c["completed_events"]), max_activity)

        # Multiplicative weighted model with log donation factor.
        raw_weight = (
            1.0
            * (1.0 + perf_norm * 0.35)
            * (1.0 + consistency_norm * 0.20)
            * (1.0 + math.log(1.0 + donation_norm) * 0.15)
            * (1.0 + activity_norm * 0.10)
        )
        c["performance_norm"] = perf_norm
        c["consistency_norm"] = consistency_norm
        c["donation_norm"] = donation_norm
        c["activity_norm"] = activity_norm
        c["raw_weight"] = raw_weight

    raw_weights = [float(c["raw_weight"]) for c in base_candidates]
    avg_weight = sum(raw_weights) / max(1, len(raw_weights))
    med_weight = _median(raw_weights)
    p95 = _percentile(raw_weights, 0.95)
    p10 = _percentile(raw_weights, 0.10)
    hard_cap = min(3.0 * med_weight if med_weight > 0 else p95, p95 * 1.2 if p95 > 0 else 1.0)
    luck_floor = max(0.5 * avg_weight if avg_weight > 0 else 0.1, p10 * 0.8 if p10 > 0 else 0.1)

    for c in base_candidates:
        clipped = max(luck_floor, min(float(c["raw_weight"]), hard_cap if hard_cap > 0 else float(c["raw_weight"])))
        c["final_weight"] = clipped

    total_weight = sum(float(c["final_weight"]) for c in base_candidates)
    for c in base_candidates:
        chance = (float(c["final_weight"]) / total_weight * 100.0) if total_weight > 0 else 0.0
        c["chance_pct"] = round(chance, 4)

    return base_candidates


async def get_active_subscription(db: AsyncSession, user_id: int) -> GolfSubscription | None:
    now = utcnow()
    stmt = (
        select(GolfSubscription)
        .where(
            GolfSubscription.user_id == user_id,
            GolfSubscription.status == "active",
            GolfSubscription.current_period_end >= now,
        )
        .order_by(GolfSubscription.current_period_end.desc())
        .limit(1)
    )
    row = await db.execute(stmt)
    return row.scalar_one_or_none()


async def require_active_subscriber(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> User:
    subscription = await get_active_subscription(db, current_user.id)
    if not subscription:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Active subscription required for this feature",
        )
    return current_user


async def get_or_create_open_draw(db: AsyncSession, now: datetime) -> GolfDraw:
    key = month_key_for(now)
    stmt = select(GolfDraw).where(GolfDraw.month_key == key).limit(1)
    row = await db.execute(stmt)
    draw = row.scalar_one_or_none()
    if draw:
        return draw

    prior_draw = (
        await db.execute(
            select(GolfDraw)
            .where(
                GolfDraw.status == "completed",
                GolfDraw.month_key < key,
                ~GolfDraw.month_key.like("%-W%"),
            )
            .order_by(GolfDraw.month_key.desc(), GolfDraw.completed_at.desc().nullslast())
            .limit(1)
        )
    ).scalar_one_or_none()
    prior_preview = prior_draw.draw_numbers if prior_draw and isinstance(prior_draw.draw_numbers, dict) else {}
    carry_in = int((prior_preview or {}).get("rollover_cents") or 0)

    draw = GolfDraw(
        month_key=key,
        status="open",
        run_at=None,
        jackpot_carry_in_cents=carry_in,
    )
    db.add(draw)
    await db.flush()
    return draw


class CharityCreateRequest(BaseModel):
    name: str = Field(min_length=2, max_length=160)
    slug: str = Field(min_length=2, max_length=180, pattern=r"^[a-z0-9-]+$")
    description: str | None = Field(default=None, max_length=2000)
    cause: str | None = Field(default=None, max_length=80)
    location: str | None = Field(default=None, max_length=120)
    website_url: HttpUrl | None = None
    hero_image_url: HttpUrl | None = None
    gallery_image_urls: list[HttpUrl] | None = None
    spotlight_text: str | None = Field(default=None, max_length=500)
    is_featured: bool | None = None
    upcoming_events: list["CharityEventInput"] | None = None


class CharityUpdateRequest(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=160)
    slug: str | None = Field(default=None, min_length=2, max_length=180, pattern=r"^[a-z0-9-]+$")
    description: str | None = Field(default=None, max_length=2000)
    cause: str | None = Field(default=None, max_length=80)
    location: str | None = Field(default=None, max_length=120)
    website_url: HttpUrl | None = None
    hero_image_url: HttpUrl | None = None
    gallery_image_urls: list[HttpUrl] | None = None
    spotlight_text: str | None = Field(default=None, max_length=500)
    is_featured: bool | None = None
    upcoming_events: list["CharityEventInput"] | None = None
    is_active: bool | None = None


class CharityEventInput(BaseModel):
    title: str = Field(min_length=2, max_length=160)
    event_date: date | None = None
    location: str | None = Field(default=None, max_length=160)
    description: str | None = Field(default=None, max_length=800)
    registration_url: HttpUrl | None = None
    image_url: HttpUrl | None = None


class CharitySelectionRequest(BaseModel):
    charity_id: str
    contribution_pct: Decimal = Field(ge=10, le=100)


class SubscriptionCheckoutCompleteRequest(BaseModel):
    plan_id: str = Field(pattern=r"^(monthly|yearly)$")
    amount_paid_cents: int = Field(gt=0)
    charity_id: str = Field(min_length=8, max_length=64)
    charity_contribution_pct: Decimal | None = Field(default=None, ge=10, le=100)
    charity_donation_cents: int | None = Field(default=None, ge=0)
    payment_provider: str = Field(default="stripe", max_length=32)
    payment_customer_id: str | None = Field(default=None, max_length=128)
    payment_subscription_id: str | None = Field(default=None, max_length=128)


class IndependentCharityDonationRequest(BaseModel):
    charity_id: str = Field(min_length=8, max_length=64)
    amount_cents: int = Field(ge=100)
    payment_provider: str = Field(default="stripe_mock", max_length=32)
    payment_reference: str | None = Field(default=None, max_length=128)


class ProfileSetupRequest(BaseModel):
    display_name: str = Field(min_length=2, max_length=120)
    skill_level: str = Field(pattern=r"^(beginner|intermediate|pro|elite)$")
    club_affiliation: str = Field(min_length=2, max_length=160)


class WalletTopupRequest(BaseModel):
    amount: float = Field(gt=0)
    payment_provider: str = Field(default="stripe_mock", max_length=32)


class ScoreCreateRequest(BaseModel):
    course_name: str = Field(min_length=2, max_length=200)
    score: int = Field(ge=1, le=45)
    played_on: date


class ScoreUpdateRequest(BaseModel):
    course_name: str | None = Field(default=None, min_length=2, max_length=200)
    score: int | None = Field(default=None, ge=1, le=45)
    played_on: date | None = None


class AdminUserUpdateRequest(BaseModel):
    username: str | None = Field(default=None, min_length=2, max_length=120)
    email: str | None = Field(default=None, min_length=5, max_length=200)
    role: str | None = Field(default=None, pattern=r"^(guest|subscriber|admin|admine)$")
    status: str | None = Field(default=None, min_length=2, max_length=30)
    profile_setup_completed: bool | None = None
    skill_level: str | None = Field(default=None, pattern=r"^(beginner|intermediate|pro|elite)$")
    club_affiliation: str | None = Field(default=None, min_length=2, max_length=160)
    profile_pic: str | None = Field(default=None, max_length=2000)


class AdminScoreUpdateRequest(BaseModel):
    course_name: str | None = Field(default=None, min_length=2, max_length=200)
    score: int | None = Field(default=None, ge=1, le=45)
    played_on: date | None = None
    is_verified: bool | None = None


class AdminSubscriptionUpdateRequest(BaseModel):
    plan_id: str | None = Field(default=None, pattern=r"^(monthly|yearly)$")
    status: str | None = Field(default=None, pattern=r"^(active|inactive|cancelled|lapsed)$")
    cancel_at_period_end: bool | None = None
    current_period_end: datetime | None = None
    renewal_date: datetime | None = None


class DrawCreateRequest(BaseModel):
    month_key: str = Field(pattern=r"^\d{4}-\d{2}$")
    jackpot_carry_in_cents: int = Field(default=0, ge=0)


class DrawSettingsUpdateRequest(BaseModel):
    weekly_prize_cents: int = Field(ge=0)
    monthly_first_prize_cents: int = Field(ge=0)
    monthly_second_prize_cents: int = Field(ge=0)
    monthly_third_prize_cents: int = Field(ge=0)
    monthly_min_events_required: int = Field(ge=1, le=50)


class DrawRunRequest(BaseModel):
    logic_mode: str = Field(default="random", pattern=r"^(random|algorithmic)$")
    draw_seed: str | None = Field(default=None, max_length=128)
    force_numbers: list[int] | None = None


class FairDrawRunRequest(BaseModel):
    draw_kind: str = Field(pattern=r"^(weekly|monthly_jackpot)$")
    cutoff_at: datetime | None = None


class WinnerClaimCreateRequest(BaseModel):
    proof_url: HttpUrl


class WinnerClaimReviewRequest(BaseModel):
    action: str = Field(pattern=r"^(approve|reject)$")
    review_notes: str | None = Field(default=None, max_length=2000)


class MarkPaidRequest(BaseModel):
    payout_reference: str = Field(min_length=2, max_length=128)


class RegisterRequest(BaseModel):
    id_token: str = Field(min_length=32)
    referral_code: str | None = Field(default=None, max_length=40)


def _build_base_username(email: str | None, full_name: str | None, firebase_uid: str) -> str:
    if full_name:
        cleaned = re.sub(r"[^a-zA-Z0-9]+", "", full_name).strip().lower()
        if len(cleaned) >= 3:
            return cleaned[:32]
    if email:
        local = email.split("@", 1)[0].strip().lower()
        cleaned = re.sub(r"[^a-zA-Z0-9._-]+", "", local)
        if len(cleaned) >= 3:
            return cleaned[:32]
    return f"user{firebase_uid[:8].lower()}"


async def _generate_unique_username(
    db: AsyncSession,
    base_username: str,
) -> str:
    candidate = base_username
    suffix = 1
    while True:
        existing_stmt = select(User).where(User.username == candidate).limit(1)
        existing = (await db.execute(existing_stmt)).scalar_one_or_none()
        if not existing:
            return candidate
        suffix += 1
        candidate = f"{base_username[:27]}{suffix:02d}"


@router.post("/auth/register", status_code=status.HTTP_201_CREATED)
async def register_with_firebase(
    payload: RegisterRequest,
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    try:
        decoded = firebase_auth.verify_id_token(payload.id_token, check_revoked=True)
    except Exception as exc:
        # Do not leak verification internals to clients.
        raise HTTPException(status_code=401, detail="Invalid Firebase token") from exc

    firebase_uid = str(decoded.get("uid") or "").strip()
    email = str(decoded.get("email") or "").strip().lower()
    full_name = str(decoded.get("name") or "").strip() or None
    picture = str(decoded.get("picture") or "").strip() or None

    if not firebase_uid:
        raise HTTPException(status_code=400, detail="Token missing UID")
    if not email:
        raise HTTPException(status_code=400, detail="Token missing email")

    by_uid_stmt = select(User).where(User.firebase_uid == firebase_uid).limit(1)
    user = (await db.execute(by_uid_stmt)).scalar_one_or_none()

    if not user:
        by_email_stmt = select(User).where(User.email == email).limit(1)
        user = (await db.execute(by_email_stmt)).scalar_one_or_none()

    created = False
    if user:
        user.firebase_uid = firebase_uid
        user.auth_method = "firebase"
        user.last_login = datetime.utcnow()
        if _is_admin_email(email):
            user.role = "admin"
        if full_name and not user.username:
            user.username = await _generate_unique_username(
                db,
                _build_base_username(email, full_name, firebase_uid),
            )
        if picture and not user.profile_pic:
            user.profile_pic = picture
    else:
        username = await _generate_unique_username(
            db,
            _build_base_username(email, full_name, firebase_uid),
        )
        user = User(
            firebase_uid=firebase_uid,
            username=username,
            email=email,
            role="admin" if _is_admin_email(email) else "guest",
            status="available",
            auth_method="firebase",
            profile_pic=picture,
            last_login=datetime.utcnow(),
        )
        db.add(user)
        created = True

    try:
        await db.commit()
    except IntegrityError as exc:
        # Race-safe path: another request inserted same Firebase UID concurrently.
        await db.rollback()
        existing = (
            await db.execute(select(User).where(User.firebase_uid == firebase_uid).limit(1))
        ).scalar_one_or_none()
        if not existing:
            raise HTTPException(status_code=409, detail="Registration conflict. Please retry.") from exc
        existing.auth_method = "firebase"
        existing.last_login = datetime.utcnow()
        if picture and not existing.profile_pic:
            existing.profile_pic = picture
        await db.commit()
        user = existing
        created = False
    await db.refresh(user)

    referral_captured = False
    referral_status = "missing_referral_code"
    if payload.referral_code:
        try:
            referral_captured, referral_status = await _capture_referral_if_eligible(
                db,
                referred_user=user,
                referral_code=payload.referral_code,
            )
            if referral_captured:
                await db.commit()
        except ProgrammingError as exc:
            if not _is_missing_relation_error(exc):
                raise
            await db.rollback()
            referral_status = "referral_schema_missing"
            referral_captured = False
        except IntegrityError:
            await db.rollback()
            referral_status = "already_captured"
            referral_captured = False

    return {
        "ok": True,
        "created": created,
        "user": {
            "id": user.id,
            "firebase_uid": user.firebase_uid,
            "email": user.email,
            "username": user.username,
            "role": user.role,
        },
        "referral": {
            "captured": referral_captured,
            "status": referral_status,
        },
    }


@router.get("/public/overview")
async def public_overview(db: AsyncSession = Depends(get_db)) -> dict[str, Any]:
    try:
        active_charities_stmt = select(func.count(GolfCharity.id)).where(GolfCharity.is_active.is_(True))
        active_charities = int((await db.execute(active_charities_stmt)).scalar_one() or 0)
        featured_charity_stmt = (
            select(GolfCharity)
            .where(
                GolfCharity.is_active.is_(True),
                GolfCharity.is_featured.is_(True),
            )
            .order_by(GolfCharity.total_raised_cents.desc(), GolfCharity.name.asc())
            .limit(1)
        )
        featured_charity = (await db.execute(featured_charity_stmt)).scalar_one_or_none()

        current_draw_stmt = (
            select(GolfDraw)
            .where(
                GolfDraw.status.in_(["open", "closed"]),
                ~GolfDraw.month_key.like("%-W%"),
            )
            .order_by(GolfDraw.month_key.desc(), GolfDraw.created_at.desc())
            .limit(1)
        )
        current_draw = (await db.execute(current_draw_stmt)).scalar_one_or_none()
        latest_published_stmt = (
            select(GolfDraw)
            .where(
                GolfDraw.status == "completed",
                ~GolfDraw.month_key.like("%-W%"),
            )
            .order_by(GolfDraw.month_key.desc(), GolfDraw.completed_at.desc().nullslast())
            .limit(1)
        )
        latest_published_draw = (await db.execute(latest_published_stmt)).scalar_one_or_none()
    except ProgrammingError as exc:
        if not _is_missing_relation_error(exc):
            raise
        active_charities = 0
        featured_charity = None
        current_draw = None
        latest_published_draw = None

    current_pool_breakdown: dict[str, Any] | None = None
    if current_draw:
        if isinstance(current_draw.draw_numbers, dict) and isinstance(current_draw.draw_numbers.get("pool_breakdown"), dict):
            current_pool_breakdown = current_draw.draw_numbers.get("pool_breakdown")
        else:
            current_pool_breakdown = await _active_subscription_pool_snapshot(
                db,
                as_of=utcnow(),
                jackpot_carry_in_cents=int(current_draw.jackpot_carry_in_cents or 0),
            )
    else:
        current_pool_breakdown = await _active_subscription_pool_snapshot(
            db,
            as_of=utcnow(),
            jackpot_carry_in_cents=0,
        )

    latest_published_preview = _serialize_draw_preview(
        latest_published_draw.draw_numbers if latest_published_draw and isinstance(latest_published_draw.draw_numbers, dict) else None
    )

    return {
        "platform": "Golf Charity Draw",
        "positioning": "Charity-first subscription app with monthly draws, percentage-based giving, and discoverable nonprofit profiles.",
        "active_charities": active_charities,
        "featured_charity": _serialize_charity(featured_charity) if featured_charity else None,
        "current_draw": {
            "id": current_draw.id,
            "month_key": current_draw.month_key,
            "status": current_draw.status,
            "pool_total_cents": int((current_pool_breakdown or {}).get("pool_total_cents") or 0),
            "jackpot_carry_in_cents": current_draw.jackpot_carry_in_cents,
            "simulated_at": current_draw.run_at,
            "has_preview": isinstance(current_draw.draw_numbers, dict),
            "active_subscriber_count": int((current_pool_breakdown or {}).get("active_subscriber_count") or 0),
            "pool_breakdown": current_pool_breakdown,
        }
        if current_draw
        else None,
        "latest_published_draw": {
            "id": latest_published_draw.id,
            "month_key": latest_published_draw.month_key,
            "completed_at": latest_published_draw.completed_at,
            "numbers": (latest_published_preview or {}).get("numbers", []),
            "pool_breakdown": (latest_published_preview or {}).get("pool_breakdown"),
        }
        if latest_published_draw
        else None,
        "cadence": "monthly",
        "draw_logic_options": ["random", "algorithmic"],
        "subscription_contribution_bps": int(POOL_CONTRIBUTION_BPS),
        "match_distribution": (current_pool_breakdown or {}).get("tier_summary", {}),
    }


@router.get("/public/plans")
async def public_plans(db: AsyncSession = Depends(get_db)) -> dict[str, Any]:
    try:
        stmt = select(GolfSubscriptionPlan).where(GolfSubscriptionPlan.is_active.is_(True)).order_by(GolfSubscriptionPlan.amount_cents.asc())
        plans = (await db.execute(stmt)).scalars().all()
    except ProgrammingError as exc:
        if not _is_missing_relation_error(exc):
            raise
        plans = []

    if not plans:
        return {
            "plans": [
                {"id": "monthly", "name": "Monthly", "interval": "monthly", "amount_cents": 999, "currency": "USD", "discount_pct": "0.00"},
                {"id": "yearly", "name": "Yearly", "interval": "yearly", "amount_cents": 4999, "currency": "USD", "discount_pct": "58.30"},
            ]
        }

    return {
        "plans": [
            {
                "id": p.id,
                "name": p.name,
                "interval": p.interval,
                "amount_cents": p.amount_cents,
                "currency": p.currency,
                "discount_pct": str(p.discount_pct),
            }
            for p in plans
        ]
    }


@router.get("/public/charities")
async def public_charities(
    search: str | None = Query(default=None, max_length=160),
    cause: str | None = Query(default=None, max_length=80),
    featured_only: bool = Query(default=False),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    try:
        stmt = (
            select(GolfCharity)
            .where(GolfCharity.is_active.is_(True))
            .order_by(GolfCharity.is_featured.desc(), GolfCharity.name.asc())
        )
        charities = (await db.execute(stmt)).scalars().all()
    except ProgrammingError as exc:
        if not _is_missing_relation_error(exc):
            raise
        charities = []

    serialized = [_serialize_charity(c) for c in charities]
    filtered = [
        charity
        for charity in serialized
        if _charity_matches_filters(
            charity,
            search=search,
            cause=cause,
            featured_only=featured_only,
        )
    ]
    available_causes = sorted({str(charity.get("cause") or "").strip() for charity in serialized})
    available_causes = [cause_name for cause_name in available_causes if cause_name]
    featured_charity = next((charity for charity in serialized if charity.get("is_featured") is True), None)
    return {
        "charities": filtered,
        "available_causes": available_causes,
        "featured_charity": featured_charity,
        "filters": {
            "search": (search or "").strip(),
            "cause": (cause or "").strip(),
            "featured_only": featured_only,
        },
    }


@router.get("/public/charities/{charity_ref}")
async def public_charity_profile(
    charity_ref: str,
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    charity = await _active_charity_by_ref(db, charity_ref, active_only=True)
    if not charity:
        raise HTTPException(status_code=404, detail="Charity not found")
    return {"charity": _serialize_charity(charity)}


@router.post("/admin/charities", status_code=status.HTTP_201_CREATED)
async def admin_create_charity(
    payload: CharityCreateRequest,
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    exists_stmt = select(GolfCharity).where(or_(GolfCharity.name == payload.name, GolfCharity.slug == payload.slug))
    exists = (await db.execute(exists_stmt)).scalar_one_or_none()
    if exists:
        raise HTTPException(status_code=409, detail="Charity with this name or slug already exists")

    charity = GolfCharity(
        name=payload.name.strip(),
        slug=payload.slug.strip().lower(),
        description=(payload.description or "").strip() or None,
        cause=(payload.cause or "").strip() or None,
        location=(payload.location or "").strip() or None,
        website_url=str(payload.website_url) if payload.website_url else None,
        hero_image_url=str(payload.hero_image_url) if payload.hero_image_url else None,
        gallery_image_urls=[str(url) for url in (payload.gallery_image_urls or [])] or None,
        upcoming_events=_serialize_charity_event_inputs(payload.upcoming_events),
        spotlight_text=(payload.spotlight_text or "").strip() or None,
        is_featured=payload.is_featured is True,
        is_active=True,
    )
    db.add(charity)
    await db.commit()
    await db.refresh(charity)
    return _serialize_charity(charity)


@router.put("/admin/charities/{charity_id}")
async def admin_update_charity(
    charity_id: str,
    payload: CharityUpdateRequest,
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    charity = (await db.execute(select(GolfCharity).where(GolfCharity.id == charity_id))).scalar_one_or_none()
    if not charity:
        raise HTTPException(status_code=404, detail="Charity not found")

    target_name = charity.name
    target_slug = charity.slug

    if payload.name is not None:
        target_name = payload.name.strip()
    if payload.slug is not None:
        target_slug = payload.slug.strip().lower()

    if target_name != charity.name or target_slug != charity.slug:
        duplicate_stmt = select(GolfCharity).where(
            GolfCharity.id != charity.id,
            or_(GolfCharity.name == target_name, GolfCharity.slug == target_slug),
        )
        duplicate = (await db.execute(duplicate_stmt)).scalar_one_or_none()
        if duplicate:
            raise HTTPException(status_code=409, detail="Charity with this name or slug already exists")

    charity.name = target_name
    charity.slug = target_slug
    if payload.description is not None:
        charity.description = payload.description.strip() or None
    if payload.cause is not None:
        charity.cause = payload.cause.strip() or None
    if payload.location is not None:
        charity.location = payload.location.strip() or None
    if payload.website_url is not None:
        charity.website_url = str(payload.website_url)
    if payload.hero_image_url is not None:
        charity.hero_image_url = str(payload.hero_image_url)
    if payload.gallery_image_urls is not None:
        charity.gallery_image_urls = [str(url) for url in payload.gallery_image_urls] or None
    if payload.upcoming_events is not None:
        charity.upcoming_events = _serialize_charity_event_inputs(payload.upcoming_events)
    if payload.spotlight_text is not None:
        charity.spotlight_text = payload.spotlight_text.strip() or None
    if payload.is_featured is not None:
        charity.is_featured = payload.is_featured
    if payload.is_active is not None:
        charity.is_active = payload.is_active

    await db.commit()
    await db.refresh(charity)
    return {**_serialize_charity(charity), "is_active": charity.is_active}


@router.delete("/admin/charities/{charity_id}")
async def admin_delete_charity(
    charity_id: str,
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    charity = (await db.execute(select(GolfCharity).where(GolfCharity.id == charity_id))).scalar_one_or_none()
    if not charity:
        raise HTTPException(status_code=404, detail="Charity not found")

    archive_suffix = charity.id.split("-")[0].lower()
    charity.name = f"{charity.name} [archived-{archive_suffix}]"
    charity.slug = f"{charity.slug}-archived-{archive_suffix}"
    charity.is_active = False
    await db.commit()
    return {"ok": True, "id": charity_id, "archived": True}


@router.post("/admin/charities/seed-defaults")
async def admin_seed_default_charities(
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    created: list[dict[str, str]] = []
    updated: list[dict[str, str]] = []
    skipped: list[dict[str, str]] = []

    for row in DEFAULT_CHARITY_SEED:
        name = row["name"].strip()
        slug = _charity_slug(name)
        exists_stmt = select(GolfCharity).where(or_(GolfCharity.name == name, GolfCharity.slug == slug))
        exists = (await db.execute(exists_stmt)).scalar_one_or_none()
        if exists:
            changed = False
            if not (exists.description or "").strip():
                exists.description = row["description"].strip()
                changed = True
            if not (exists.cause or "").strip():
                exists.cause = str(row.get("cause") or "").strip() or None
                changed = True
            if not (exists.location or "").strip():
                exists.location = str(row.get("location") or "").strip() or None
                changed = True
            if not (exists.website_url or "").strip():
                exists.website_url = row["website_url"].strip()
                changed = True
            if not (exists.hero_image_url or "").strip():
                exists.hero_image_url = str(row.get("hero_image_url") or "").strip() or None
                changed = True
            if not _normalize_string_list(exists.gallery_image_urls):
                exists.gallery_image_urls = _normalize_string_list(row.get("gallery_image_urls")) or None
                changed = True
            if not _normalize_charity_events(exists.upcoming_events):
                exists.upcoming_events = _normalize_charity_events(row.get("upcoming_events")) or None
                changed = True
            if not (exists.spotlight_text or "").strip():
                exists.spotlight_text = str(row.get("spotlight_text") or "").strip() or None
                changed = True
            if row.get("is_featured") is True and exists.is_featured is not True:
                exists.is_featured = True
                changed = True
            if changed:
                updated.append({"name": name, "slug": slug})
            else:
                skipped.append({"name": name, "reason": "already_exists"})
            continue

        db.add(
            GolfCharity(
                name=name,
                slug=slug,
                description=row["description"].strip(),
                cause=str(row.get("cause") or "").strip() or None,
                location=str(row.get("location") or "").strip() or None,
                website_url=row["website_url"].strip(),
                hero_image_url=str(row.get("hero_image_url") or "").strip() or None,
                gallery_image_urls=_normalize_string_list(row.get("gallery_image_urls")) or None,
                upcoming_events=_normalize_charity_events(row.get("upcoming_events")) or None,
                spotlight_text=str(row.get("spotlight_text") or "").strip() or None,
                is_featured=row.get("is_featured") is True,
                is_active=True,
            )
        )
        created.append({"name": name, "slug": slug})

    await db.commit()
    return {
        "ok": True,
        "created": created,
        "updated": updated,
        "skipped": skipped,
        "total": len(DEFAULT_CHARITY_SEED),
    }


@router.get("/admin/charities/donations")
async def admin_charity_donations(
    charity_id: str | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    summary_stmt = (
        select(
            GolfCharity.id,
            GolfCharity.name,
            GolfCharity.total_raised_cents,
            func.coalesce(func.count(GolfCharityDonation.id), 0),
            func.coalesce(func.sum(GolfCharityDonation.amount_cents), 0),
        )
        .outerjoin(GolfCharityDonation, GolfCharityDonation.charity_id == GolfCharity.id)
        .where(GolfCharity.is_active.is_(True))
        .group_by(GolfCharity.id, GolfCharity.name, GolfCharity.total_raised_cents)
        .order_by(GolfCharity.name.asc())
    )
    if charity_id:
        summary_stmt = summary_stmt.where(GolfCharity.id == charity_id)

    summary_rows = (await db.execute(summary_stmt)).all()

    donations_stmt = (
        select(GolfCharityDonation, GolfCharity, User)
        .join(GolfCharity, GolfCharity.id == GolfCharityDonation.charity_id)
        .join(User, User.id == GolfCharityDonation.user_id)
        .order_by(GolfCharityDonation.created_at.desc())
        .limit(limit)
    )
    if charity_id:
        donations_stmt = donations_stmt.where(GolfCharityDonation.charity_id == charity_id)

    donation_rows = (await db.execute(donations_stmt)).all()

    return {
        "summary": [
            {
                "charity_id": row[0],
                "charity_name": row[1],
                "total_raised_cents": int(row[2] or 0),
                "donation_count": int(row[3] or 0),
                "ledger_total_cents": int(row[4] or 0),
            }
            for row in summary_rows
        ],
        "donations": [
            {
                "id": donation.id,
                "charity_id": donation.charity_id,
                "charity_name": charity.name,
                "user_id": donor.id,
                "user_email": donor.email,
                "subscription_id": donation.subscription_id,
                "donation_type": "subscription" if donation.subscription_id else "independent",
                "amount_cents": int(donation.amount_cents or 0),
                "currency": donation.currency,
                "payment_provider": donation.payment_provider,
                "payment_reference": donation.payment_reference,
                "created_at": donation.created_at,
            }
            for donation, charity, donor in donation_rows
        ],
    }


@router.get("/me/subscription")
async def my_subscription(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    now = utcnow()
    stmt = (
        select(GolfSubscription)
        .where(GolfSubscription.user_id == current_user.id)
        .order_by(GolfSubscription.current_period_end.desc())
        .limit(1)
    )
    sub = (await db.execute(stmt)).scalar_one_or_none()

    if not sub:
        return {"has_subscription": False, "status": "inactive"}

    derived_status = sub.status
    if sub.status == "active" and sub.current_period_end < now:
        derived_status = "lapsed"

    return {
        "has_subscription": True,
        "id": sub.id,
        "plan_id": sub.plan_id,
        "status": derived_status,
        "renewal_date": sub.renewal_date,
        "current_period_end": sub.current_period_end,
        "cancel_at_period_end": sub.cancel_at_period_end,
    }


@router.get("/me/profile")
async def my_profile(
    current_user: User = Depends(get_current_user),
) -> dict[str, Any]:
    return {
        "id": current_user.id,
        "email": current_user.email,
        "display_name": current_user.username,
        "role": (current_user.role or "guest"),
        "profile_setup_completed": bool(current_user.profile_setup_completed),
        "skill_level": current_user.skill_level,
        "club_affiliation": current_user.club_affiliation,
    }


@router.get("/me/referral")
async def my_referral(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    try:
        code_row = await _ensure_referral_code_for_user(db, current_user.id)
        stats_rows = (
            await db.execute(
                select(
                    GolfReferral.status,
                    func.count(GolfReferral.id),
                    func.coalesce(func.sum(GolfReferral.reward_amount_usd), Decimal("0.00")),
                )
                .where(GolfReferral.referrer_user_id == current_user.id)
                .group_by(GolfReferral.status)
            )
        ).all()
    except ProgrammingError as exc:
        if not _is_missing_relation_error(exc):
            raise
        raise HTTPException(
            status_code=503,
            detail="Referral schema is missing. Apply the latest referral SQL migration.",
        ) from exc

    captured = 0
    rewarded = 0
    total_bonus_usd = Decimal("0.00")
    for status_name, count_value, amount_value in stats_rows:
        status_key = str(status_name or "").strip().lower()
        if status_key == "captured":
            captured += int(count_value or 0)
        if status_key == "rewarded":
            rewarded += int(count_value or 0)
            total_bonus_usd += Decimal(amount_value or 0)

    referral_code = code_row.code
    return {
        "referral_code": referral_code,
        "referral_link": _build_referral_link(request, referral_code),
        "bonus_amount_usd": REFERRAL_BONUS_USD,
        "captured_count": captured,
        "rewarded_count": rewarded,
        "total_bonus_usd": float(total_bonus_usd),
    }


@router.post("/me/profile/setup")
async def complete_profile_setup(
    payload: ProfileSetupRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    if not current_user.profile_setup_completed:
        current_user.profile_setup_completed = True
        requested_name = payload.display_name.strip()
        if requested_name != current_user.username:
            current_user.username = await _generate_unique_username(db, requested_name.lower())
        current_user.skill_level = payload.skill_level
        current_user.club_affiliation = payload.club_affiliation.strip()
        await db.commit()
        await db.refresh(current_user)
    return {
        "ok": True,
        "profile_setup_completed": bool(current_user.profile_setup_completed),
        "display_name": current_user.username,
        "skill_level": current_user.skill_level,
        "club_affiliation": current_user.club_affiliation,
    }


@router.get("/me/wallet")
async def my_wallet(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    wallet_stmt = select(Wallet).where(Wallet.user_id == current_user.id).limit(1)
    wallet = (await db.execute(wallet_stmt)).scalar_one_or_none()
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
        await db.commit()
        await db.refresh(wallet)

    return {
        "user_id": current_user.id,
        "available_amount": wallet_available_amount(wallet),
        "total_topped_up": float(wallet.total_topups or wallet.total_purchased or 0.0),
        "total_donated": float(wallet.total_donated or 0.0),
        "last_updated": wallet.last_updated,
    }


@router.post("/me/wallet/topup/checkout-complete")
async def wallet_topup_checkout_complete(
    payload: WalletTopupRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    wallet_stmt = select(Wallet).where(Wallet.user_id == current_user.id).limit(1)
    wallet = (await db.execute(wallet_stmt)).scalar_one_or_none()
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

    amount = float(payload.amount)
    wallet.available_balance = wallet_available_amount(wallet) + amount
    wallet.total_topups = float(wallet.total_topups or wallet.total_purchased or 0.0) + amount
    # Keep legacy fields in sync for backward compatibility.
    wallet.token_balance = float(wallet.available_balance or 0.0)
    wallet.total_purchased = float(wallet.total_topups or 0.0)
    wallet.last_updated = utcnow()

    tx = Transaction(
        amount=amount,
        statuz="SUCCESS",
        purpose="WALLET_TOPUP",
        purpose_ref=f"stripe_mock_{int(datetime.utcnow().timestamp())}",
        metadata_json={"provider": payload.payment_provider},
        consumed_at=utcnow(),
        user_id=current_user.id,
    )
    db.add(tx)
    await db.flush()
    db.add(
        WalletLedger(
            user_id=current_user.id,
            entry_type="topup",
            amount=amount,
            currency="USD",
            reference_type="wallet_topup",
            reference_id=str(tx.id),
            status="completed",
            metadata_json={"provider": payload.payment_provider},
        )
    )
    await db.commit()
    await db.refresh(wallet)
    await db.refresh(tx)

    return {
        "ok": True,
        "transaction_id": tx.id,
        "available_amount": wallet_available_amount(wallet),
        "total_topped_up": float(wallet.total_topups or wallet.total_purchased or 0.0),
        "total_donated": float(wallet.total_donated or 0.0),
        "last_updated": wallet.last_updated,
    }


@router.post("/me/subscription/checkout-complete")
async def subscription_checkout_complete(
    payload: SubscriptionCheckoutCompleteRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    expected_amount_cents = SUBSCRIPTION_AMOUNT_CENTS_BY_PLAN.get(payload.plan_id)
    if expected_amount_cents is None:
        raise HTTPException(status_code=400, detail="Unsupported subscription plan")
    if int(payload.amount_paid_cents) != int(expected_amount_cents):
        raise HTTPException(
            status_code=400,
            detail=(
                f"Invalid amount for plan '{payload.plan_id}'. "
                f"Expected {expected_amount_cents} cents."
            ),
        )

    now = utcnow()
    duration = timedelta(days=30 if payload.plan_id == "monthly" else 365)

    charity_stmt = select(GolfCharity).where(
        and_(
            GolfCharity.id == payload.charity_id,
            GolfCharity.is_active.is_(True),
        )
    )
    charity = (await db.execute(charity_stmt)).scalar_one_or_none()
    if not charity:
        raise HTTPException(status_code=404, detail="Selected charity is not available")

    setting_stmt = select(GolfUserCharitySetting).where(GolfUserCharitySetting.user_id == current_user.id)
    setting = (await db.execute(setting_stmt)).scalar_one_or_none()

    resolved_charity_pct = payload.charity_contribution_pct
    if resolved_charity_pct is None and payload.charity_donation_cents is not None:
        resolved_charity_pct = (
            Decimal(str(payload.charity_donation_cents))
            / Decimal(str(payload.amount_paid_cents))
            * Decimal("100")
        ).quantize(Decimal("0.01"))
    if resolved_charity_pct is None and setting and setting.charity_id == payload.charity_id:
        resolved_charity_pct = Decimal(str(setting.contribution_pct))
    if resolved_charity_pct is None:
        raise HTTPException(
            status_code=400,
            detail="Charity contribution percentage is required before subscription checkout",
        )
    if resolved_charity_pct < MIN_CHARITY_CONTRIBUTION_PCT:
        raise HTTPException(
            status_code=400,
            detail=f"Minimum charity contribution is {MIN_CHARITY_CONTRIBUTION_PCT}% of the subscription fee",
        )

    if payload.charity_donation_cents is not None and payload.charity_contribution_pct is None:
        charity_donation_cents = int(payload.charity_donation_cents)
    else:
        charity_donation_cents = int(
            round(float(payload.amount_paid_cents) * float(resolved_charity_pct) / 100.0)
        )

    existing_stmt = (
        select(GolfSubscription)
        .where(GolfSubscription.user_id == current_user.id)
        .order_by(GolfSubscription.current_period_end.desc())
        .limit(1)
    )
    sub = (await db.execute(existing_stmt)).scalar_one_or_none()
    prior_payments_count_stmt = select(func.count(GolfSubscriptionPayment.id)).where(
        GolfSubscriptionPayment.user_id == current_user.id
    )
    prior_payments_count = int((await db.execute(prior_payments_count_stmt)).scalar_one() or 0)

    if sub and sub.current_period_end > now:
        period_start = sub.current_period_end
    else:
        period_start = now

    period_end = period_start + duration

    if sub:
        sub.plan_id = payload.plan_id
        sub.status = "active"
        sub.current_period_start = period_start
        sub.current_period_end = period_end
        sub.renewal_date = period_end
        sub.cancel_at_period_end = False
        sub.cancelled_at = None
        sub.lapsed_at = None
        sub.payment_provider = payload.payment_provider
        sub.payment_customer_id = payload.payment_customer_id
        sub.payment_subscription_id = payload.payment_subscription_id
        target_sub = sub
    else:
        target_sub = GolfSubscription(
            user_id=current_user.id,
            plan_id=payload.plan_id,
            status="active",
            started_at=now,
            current_period_start=period_start,
            current_period_end=period_end,
            renewal_date=period_end,
            payment_provider=payload.payment_provider,
            payment_customer_id=payload.payment_customer_id,
            payment_subscription_id=payload.payment_subscription_id,
        )
        db.add(target_sub)
        await db.flush()

    current_user.role = "subscriber"

    # Persist subscription payment and charity donation as separate records.
    db.add(
        GolfSubscriptionPayment(
            user_id=current_user.id,
            subscription_id=target_sub.id,
            plan_id=payload.plan_id,
            amount_cents=payload.amount_paid_cents,
            currency="USD",
            payment_provider=payload.payment_provider,
            payment_reference=payload.payment_subscription_id,
        )
    )
    db.add(
        GolfCharityDonation(
            user_id=current_user.id,
            charity_id=payload.charity_id,
            subscription_id=target_sub.id,
            amount_cents=charity_donation_cents,
            currency="USD",
            payment_provider=payload.payment_provider,
            payment_reference=payload.payment_subscription_id,
        )
    )
    charity.total_raised_cents = int(charity.total_raised_cents or 0) + int(charity_donation_cents)

    if setting:
        setting.charity_id = payload.charity_id
        setting.contribution_pct = resolved_charity_pct
    else:
        db.add(
            GolfUserCharitySetting(
                user_id=current_user.id,
                charity_id=payload.charity_id,
                contribution_pct=resolved_charity_pct,
            )
        )

    contribution = int(payload.amount_paid_cents * POOL_CONTRIBUTION_BPS / 10000)
    draw = await get_or_create_open_draw(db, now)

    ledger = GolfPoolLedger(
        user_id=current_user.id,
        subscription_id=target_sub.id,
        draw_id=draw.id,
        amount_cents=contribution,
        source="subscription_contribution",
    )
    db.add(ledger)
    live_pool_breakdown = await _active_subscription_pool_snapshot(
        db,
        as_of=now,
        jackpot_carry_in_cents=int(draw.jackpot_carry_in_cents or 0),
    )
    draw.pool_total_cents = int(live_pool_breakdown.get("pool_total_cents") or 0)
    draw.match5_pool_cents = int(
        (((live_pool_breakdown.get("tier_summary") or {}).get("match_5") or {}).get("pool_cents")) or 0
    )
    draw.match4_pool_cents = int(
        (((live_pool_breakdown.get("tier_summary") or {}).get("match_4") or {}).get("pool_cents")) or 0
    )
    draw.match3_pool_cents = int(
        (((live_pool_breakdown.get("tier_summary") or {}).get("match_3") or {}).get("pool_cents")) or 0
    )

    referral_bonus_awarded_usd = 0.0
    referral_bonus_awarded_to_user_id: int | None = None
    if prior_payments_count == 0:
        try:
            referral = (
                await db.execute(
                    select(GolfReferral)
                    .where(
                        GolfReferral.referred_user_id == current_user.id,
                        GolfReferral.status.in_(["captured", "qualified"]),
                    )
                    .order_by(GolfReferral.captured_at.asc())
                    .limit(1)
                )
            ).scalar_one_or_none()
            if referral:
                bonus_amount = float(referral.reward_amount_usd or REFERRAL_BONUS_USD)
                referrer_wallet = (
                    await db.execute(
                        select(Wallet).where(Wallet.user_id == referral.referrer_user_id).limit(1)
                    )
                ).scalar_one_or_none()
                if not referrer_wallet:
                    referrer_wallet = Wallet(
                        user_id=referral.referrer_user_id,
                        available_balance=0.0,
                        total_topups=0.0,
                        total_donated=0.0,
                        token_balance=0.0,
                        total_purchased=0.0,
                    )
                    db.add(referrer_wallet)
                    await db.flush()

                referrer_wallet.available_balance = wallet_available_amount(referrer_wallet) + bonus_amount
                referrer_wallet.token_balance = float(referrer_wallet.available_balance or 0.0)
                referrer_wallet.last_updated = now
                db.add(
                    WalletLedger(
                        user_id=referral.referrer_user_id,
                        entry_type="referral_bonus",
                        amount=bonus_amount,
                        currency="USD",
                        reference_type="golf_referral",
                        reference_id=referral.id,
                        status="completed",
                        metadata_json={
                            "referred_user_id": current_user.id,
                            "subscription_id": target_sub.id,
                            "payment_provider": payload.payment_provider,
                        },
                    )
                )
                referral.status = "rewarded"
                referral.qualified_at = referral.qualified_at or now
                referral.rewarded_at = now
                referral.rewarded_subscription_id = target_sub.id
                db.add(
                    TournamentInboxMessage(
                        recipient_user_id=referral.referrer_user_id,
                        sender_user_id=current_user.id,
                        message_type="system",
                        title="Referral Bonus Added",
                        body=(
                            f"You earned ${bonus_amount:.2f} referral bonus after "
                            f"{current_user.username} completed their first subscription."
                        ),
                        status="unread",
                    )
                )
                referral_bonus_awarded_usd = bonus_amount
                referral_bonus_awarded_to_user_id = int(referral.referrer_user_id)
        except ProgrammingError as exc:
            if not _is_missing_relation_error(exc):
                raise

    await db.commit()
    await db.refresh(target_sub)

    return {
        "subscription_id": target_sub.id,
        "status": target_sub.status,
        "renewal_date": target_sub.renewal_date,
        "draw_id": draw.id,
        "pool_contribution_cents": contribution,
        "charity_id": payload.charity_id,
        "charity_contribution_pct": str(resolved_charity_pct),
        "charity_donation_cents": charity_donation_cents,
        "subscription_amount_cents": payload.amount_paid_cents,
        "referral_bonus_awarded_usd": referral_bonus_awarded_usd,
        "referral_bonus_awarded_to_user_id": referral_bonus_awarded_to_user_id,
    }


@router.post("/me/subscription/cancel")
async def cancel_subscription(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = (
        select(GolfSubscription)
        .where(GolfSubscription.user_id == current_user.id)
        .order_by(GolfSubscription.current_period_end.desc())
        .limit(1)
    )
    sub = (await db.execute(stmt)).scalar_one_or_none()
    if not sub:
        raise HTTPException(status_code=404, detail="No subscription found")

    sub.cancel_at_period_end = True
    sub.cancelled_at = utcnow()
    if sub.current_period_end <= utcnow():
        current_user.role = "guest"
    await db.commit()

    return {
        "subscription_id": sub.id,
        "cancel_at_period_end": True,
        "current_period_end": sub.current_period_end,
    }


@router.get("/me/scores")
async def my_scores(
    limit: int = Query(default=5, ge=1, le=5),
    current_user: User = Depends(require_active_subscriber),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = (
        select(GolfScore)
        .where(GolfScore.user_id == current_user.id)
        .order_by(GolfScore.played_on.desc(), GolfScore.created_at.desc())
        .limit(limit)
    )
    scores = (await db.execute(stmt)).scalars().all()
    return {
        "scores": [
            {
                "id": s.id,
                "course_name": s.course_name,
                "score": s.score,
                "played_on": s.played_on,
                "is_verified": s.is_verified,
                "created_at": s.created_at,
            }
            for s in scores
        ]
    }


@router.post("/me/scores", status_code=status.HTTP_201_CREATED)
async def create_score(
    payload: ScoreCreateRequest,
    current_user: User = Depends(require_active_subscriber),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    score = GolfScore(
        user_id=current_user.id,
        course_name=payload.course_name.strip(),
        score=payload.score,
        played_on=payload.played_on,
        source="manual",
    )
    db.add(score)
    await db.flush()

    # Keep only the latest 5 scores per user (new score replaces oldest).
    score_history_stmt = (
        select(GolfScore)
        .where(GolfScore.user_id == current_user.id)
        .order_by(GolfScore.played_on.desc(), GolfScore.created_at.desc())
    )
    score_history = (await db.execute(score_history_stmt)).scalars().all()
    if len(score_history) > 5:
        stale_ids = [s.id for s in score_history[5:]]
        if stale_ids:
            await db.execute(
                delete(GolfScore).where(
                    GolfScore.user_id == current_user.id,
                    GolfScore.id.in_(stale_ids),
                )
            )

    draw = await get_or_create_open_draw(db, utcnow())

    score_window_stmt = (
        select(GolfScore)
        .where(GolfScore.user_id == current_user.id)
        .order_by(GolfScore.played_on.desc(), GolfScore.created_at.desc())
        .limit(5)
    )
    recent_scores = (await db.execute(score_window_stmt)).scalars().all()

    entry_created = False
    entry_id: str | None = None
    if len(recent_scores) == 5 and draw.status == "open":
        score_values = [s.score for s in reversed(recent_scores)]
        picks = derive_pick_numbers(score_values)

        entry = GolfDrawEntry(
            user_id=current_user.id,
            draw_id=draw.id,
            score_id=score.id,
            score_window={
                "scores": score_values,
                "derived_numbers": picks,
                "entered_at": utcnow().isoformat(),
            },
            numbers=picks,
        )
        db.add(entry)
        await db.flush()
        entry_created = True
        entry_id = entry.id

    await db.commit()
    await db.refresh(score)

    return {
        "score": {
            "id": score.id,
            "course_name": score.course_name,
            "score": score.score,
            "played_on": score.played_on,
        },
        "draw_entry_created": entry_created,
        "draw_entry_id": entry_id,
        "rolling_window_ready": len(recent_scores) == 5,
    }


@router.put("/me/scores/{score_id}")
async def update_score(
    score_id: str,
    payload: ScoreUpdateRequest,
    current_user: User = Depends(require_active_subscriber),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = select(GolfScore).where(and_(GolfScore.id == score_id, GolfScore.user_id == current_user.id))
    score = (await db.execute(stmt)).scalar_one_or_none()
    if not score:
        raise HTTPException(status_code=404, detail="Score not found")

    if payload.course_name is not None:
        score.course_name = payload.course_name.strip()
    if payload.score is not None:
        score.score = payload.score
    if payload.played_on is not None:
        score.played_on = payload.played_on

    await db.commit()
    await db.refresh(score)

    return {
        "id": score.id,
        "course_name": score.course_name,
        "score": score.score,
        "played_on": score.played_on,
    }


def _serialize_admin_user(user: User) -> dict[str, Any]:
    return {
        "id": user.id,
        "username": user.username,
        "email": user.email,
        "role": user.role,
        "status": user.status,
        "auth_method": user.auth_method,
        "profile_setup_completed": bool(user.profile_setup_completed),
        "skill_level": user.skill_level,
        "club_affiliation": user.club_affiliation,
        "profile_pic": user.profile_pic,
        "last_login": user.last_login,
    }


def _serialize_admin_score(score: GolfScore) -> dict[str, Any]:
    return {
        "id": score.id,
        "user_id": score.user_id,
        "course_name": score.course_name,
        "score": score.score,
        "played_on": score.played_on,
        "is_verified": bool(score.is_verified),
        "source": score.source,
        "created_at": score.created_at,
        "updated_at": score.updated_at,
    }


def _serialize_admin_subscription(sub: GolfSubscription) -> dict[str, Any]:
    return {
        "id": sub.id,
        "user_id": sub.user_id,
        "plan_id": sub.plan_id,
        "status": sub.status,
        "started_at": sub.started_at,
        "current_period_start": sub.current_period_start,
        "current_period_end": sub.current_period_end,
        "renewal_date": sub.renewal_date,
        "cancel_at_period_end": bool(sub.cancel_at_period_end),
        "cancelled_at": sub.cancelled_at,
        "lapsed_at": sub.lapsed_at,
        "payment_provider": sub.payment_provider,
        "payment_customer_id": sub.payment_customer_id,
        "payment_subscription_id": sub.payment_subscription_id,
        "created_at": sub.created_at,
        "updated_at": sub.updated_at,
    }


async def _sync_user_role_with_subscription_state(db: AsyncSession, user: User) -> None:
    role = (user.role or "").strip().lower()
    if role in {"admin", "admine"}:
        return

    has_active_stmt = select(func.count(GolfSubscription.id)).where(
        GolfSubscription.user_id == user.id,
        GolfSubscription.status == "active",
        GolfSubscription.current_period_end >= utcnow(),
    )
    has_active = int((await db.execute(has_active_stmt)).scalar_one() or 0) > 0
    user.role = "subscriber" if has_active else "guest"


@router.get("/admin/users")
async def admin_list_users(
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0, le=5000),
    query: str | None = Query(default=None, min_length=1, max_length=120),
    role: str | None = Query(default=None),
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = select(User)

    if query:
        like = f"%{query.strip().lower()}%"
        stmt = stmt.where(
            or_(
                func.lower(User.username).like(like),
                func.lower(User.email).like(like),
                func.lower(func.coalesce(User.club_affiliation, "")).like(like),
            )
        )
    if role and role.strip():
        stmt = stmt.where(User.role == role.strip().lower())

    count_stmt = select(func.count()).select_from(stmt.subquery())
    total = int((await db.execute(count_stmt)).scalar_one() or 0)

    rows_stmt = (
        stmt.order_by(User.id.desc())
        .offset(offset)
        .limit(limit)
    )
    users = (await db.execute(rows_stmt)).scalars().all()

    ids = [u.id for u in users]
    latest_sub_map: dict[int, GolfSubscription] = {}
    score_count_map: dict[int, int] = {}

    if ids:
        latest_sub_stmt = (
            select(GolfSubscription)
            .where(GolfSubscription.user_id.in_(ids))
            .order_by(
                GolfSubscription.user_id.asc(),
                GolfSubscription.current_period_end.desc(),
            )
        )
        latest_sub_rows = (await db.execute(latest_sub_stmt)).scalars().all()
        for row in latest_sub_rows:
            latest_sub_map.setdefault(int(row.user_id), row)

        score_count_stmt = (
            select(GolfScore.user_id, func.count(GolfScore.id))
            .where(GolfScore.user_id.in_(ids))
            .group_by(GolfScore.user_id)
        )
        for user_id, count in (await db.execute(score_count_stmt)).all():
            score_count_map[int(user_id)] = int(count or 0)

    return {
        "total": total,
        "items": [
            {
                **_serialize_admin_user(u),
                "score_count": score_count_map.get(int(u.id), 0),
                "latest_subscription": _serialize_admin_subscription(latest_sub_map[int(u.id)])
                if int(u.id) in latest_sub_map
                else None,
            }
            for u in users
        ],
    }


@router.put("/admin/users/{user_id}")
async def admin_update_user(
    user_id: int,
    payload: AdminUserUpdateRequest,
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if payload.username is not None:
        user.username = payload.username.strip()
    if payload.email is not None:
        user.email = payload.email.strip().lower()
    if payload.role is not None:
        user.role = payload.role.strip().lower()
    if payload.status is not None:
        user.status = payload.status.strip()
    if payload.profile_setup_completed is not None:
        user.profile_setup_completed = payload.profile_setup_completed
    if payload.skill_level is not None:
        user.skill_level = payload.skill_level
    if payload.club_affiliation is not None:
        user.club_affiliation = payload.club_affiliation.strip()
    if payload.profile_pic is not None:
        user.profile_pic = payload.profile_pic.strip()

    try:
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(status_code=409, detail="Username or email already in use") from exc

    await db.refresh(user)
    return {"user": _serialize_admin_user(user)}


@router.get("/admin/users/{user_id}/scores")
async def admin_list_user_scores(
    user_id: int,
    limit: int = Query(default=50, ge=1, le=200),
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    exists = (await db.execute(select(User.id).where(User.id == user_id))).scalar_one_or_none()
    if not exists:
        raise HTTPException(status_code=404, detail="User not found")

    stmt = (
        select(GolfScore)
        .where(GolfScore.user_id == user_id)
        .order_by(GolfScore.played_on.desc(), GolfScore.created_at.desc())
        .limit(limit)
    )
    rows = (await db.execute(stmt)).scalars().all()
    return {"items": [_serialize_admin_score(row) for row in rows]}


@router.put("/admin/scores/{score_id}")
async def admin_update_score(
    score_id: str,
    payload: AdminScoreUpdateRequest,
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    row = (await db.execute(select(GolfScore).where(GolfScore.id == score_id))).scalar_one_or_none()
    if not row:
        raise HTTPException(status_code=404, detail="Score not found")

    if payload.course_name is not None:
        row.course_name = payload.course_name.strip()
    if payload.score is not None:
        row.score = payload.score
    if payload.played_on is not None:
        row.played_on = payload.played_on
    if payload.is_verified is not None:
        row.is_verified = payload.is_verified

    await db.commit()
    await db.refresh(row)
    return {"score": _serialize_admin_score(row)}


@router.get("/admin/users/{user_id}/subscriptions")
async def admin_list_user_subscriptions(
    user_id: int,
    limit: int = Query(default=20, ge=1, le=100),
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    exists = (await db.execute(select(User.id).where(User.id == user_id))).scalar_one_or_none()
    if not exists:
        raise HTTPException(status_code=404, detail="User not found")

    stmt = (
        select(GolfSubscription)
        .where(GolfSubscription.user_id == user_id)
        .order_by(GolfSubscription.current_period_end.desc())
        .limit(limit)
    )
    rows = (await db.execute(stmt)).scalars().all()
    return {"items": [_serialize_admin_subscription(row) for row in rows]}


@router.put("/admin/subscriptions/{subscription_id}")
async def admin_update_subscription(
    subscription_id: str,
    payload: AdminSubscriptionUpdateRequest,
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    row = (
        await db.execute(select(GolfSubscription).where(GolfSubscription.id == subscription_id))
    ).scalar_one_or_none()
    if not row:
        raise HTTPException(status_code=404, detail="Subscription not found")

    if payload.plan_id is not None:
        row.plan_id = payload.plan_id
    if payload.status is not None:
        row.status = payload.status
        if payload.status == "cancelled":
            row.cancelled_at = utcnow()
            row.cancel_at_period_end = True
        if payload.status == "lapsed":
            row.lapsed_at = utcnow()
    if payload.cancel_at_period_end is not None:
        row.cancel_at_period_end = payload.cancel_at_period_end
    if payload.current_period_end is not None:
        row.current_period_end = payload.current_period_end
    if payload.renewal_date is not None:
        row.renewal_date = payload.renewal_date

    user = (await db.execute(select(User).where(User.id == row.user_id))).scalar_one_or_none()
    if user:
        await _sync_user_role_with_subscription_state(db, user)

    await db.commit()
    await db.refresh(row)
    return {"subscription": _serialize_admin_subscription(row)}


@router.get("/me/charity-selection")
async def get_my_charity_selection(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = select(GolfUserCharitySetting).where(GolfUserCharitySetting.user_id == current_user.id)
    row = (await db.execute(stmt)).scalar_one_or_none()
    if not row:
        return {
            "selected": False,
            "minimum_contribution_pct": str(MIN_CHARITY_CONTRIBUTION_PCT),
        }
    charity = await _active_charity_by_ref(db, row.charity_id, active_only=False)
    return {
        "selected": True,
        "charity_id": row.charity_id,
        "contribution_pct": str(row.contribution_pct),
        "minimum_contribution_pct": str(MIN_CHARITY_CONTRIBUTION_PCT),
        "charity": _serialize_charity(charity) if charity else None,
        "updated_at": row.updated_at,
    }


@router.post("/me/charity-selection")
async def set_my_charity_selection(
    payload: CharitySelectionRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    charity_stmt = select(GolfCharity).where(and_(GolfCharity.id == payload.charity_id, GolfCharity.is_active.is_(True)))
    charity = (await db.execute(charity_stmt)).scalar_one_or_none()
    if not charity:
        raise HTTPException(status_code=404, detail="Charity not found or inactive")

    stmt = select(GolfUserCharitySetting).where(GolfUserCharitySetting.user_id == current_user.id)
    setting = (await db.execute(stmt)).scalar_one_or_none()

    if setting:
        setting.charity_id = payload.charity_id
        setting.contribution_pct = payload.contribution_pct
    else:
        setting = GolfUserCharitySetting(
            user_id=current_user.id,
            charity_id=payload.charity_id,
            contribution_pct=payload.contribution_pct,
        )
        db.add(setting)

    await db.commit()
    return {
        "ok": True,
        "charity_id": payload.charity_id,
        "contribution_pct": str(payload.contribution_pct),
        "minimum_contribution_pct": str(MIN_CHARITY_CONTRIBUTION_PCT),
        "charity": _serialize_charity(charity),
    }


@router.post("/me/charity-donations")
async def create_independent_charity_donation(
    payload: IndependentCharityDonationRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    charity = await _active_charity_by_ref(db, payload.charity_id, active_only=True)
    if not charity:
        raise HTTPException(status_code=404, detail="Charity not found or inactive")

    donation = GolfCharityDonation(
        user_id=current_user.id,
        charity_id=charity.id,
        subscription_id=None,
        amount_cents=payload.amount_cents,
        currency="USD",
        payment_provider=payload.payment_provider,
        payment_reference=(payload.payment_reference or "").strip() or None,
    )
    db.add(donation)
    charity.total_raised_cents = int(charity.total_raised_cents or 0) + int(payload.amount_cents)
    await db.commit()
    await db.refresh(donation)
    return {
        "ok": True,
        "donation_id": donation.id,
        "charity_id": charity.id,
        "amount_cents": int(donation.amount_cents or 0),
        "currency": donation.currency,
        "donation_type": "independent",
        "created_at": donation.created_at,
    }


@router.get("/me/participation")
async def my_participation(
    current_user: User = Depends(require_active_subscriber),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    draws_entered_stmt = select(func.count(GolfDrawEntry.id)).where(GolfDrawEntry.user_id == current_user.id)
    draws_entered = int((await db.execute(draws_entered_stmt)).scalar_one() or 0)

    upcoming_stmt = (
        select(func.count(GolfDraw.id))
        .where(
            GolfDraw.status == "open",
            ~GolfDraw.month_key.like("%-W%"),
        )
        .where(or_(GolfDraw.run_at.is_(None), GolfDraw.run_at >= utcnow()))
    )
    upcoming_draws = int((await db.execute(upcoming_stmt)).scalar_one() or 0)

    wins_stmt = (
        select(func.count(GolfDrawEntry.id))
        .where(GolfDrawEntry.user_id == current_user.id, GolfDrawEntry.is_winner.is_(True))
    )
    wins = int((await db.execute(wins_stmt)).scalar_one() or 0)

    return {
        "draws_entered": draws_entered,
        "upcoming_draws": upcoming_draws,
        "wins": wins,
    }


@router.get("/me/draws/summary")
async def my_draws_summary(
    limit: int = Query(default=12, ge=1, le=50),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    entries_stmt = (
        select(GolfDrawEntry, GolfDraw, GolfWinnerClaim)
        .join(GolfDraw, GolfDraw.id == GolfDrawEntry.draw_id)
        .outerjoin(GolfWinnerClaim, GolfWinnerClaim.draw_entry_id == GolfDrawEntry.id)
        .where(
            GolfDrawEntry.user_id == current_user.id,
            ~GolfDraw.month_key.like("%-W%"),
        )
        .order_by(GolfDraw.month_key.desc(), GolfDraw.run_at.desc().nullslast(), GolfDraw.created_at.desc())
        .limit(limit)
    )
    rows = (await db.execute(entries_stmt)).all()

    items: list[dict[str, Any]] = []
    latest_monthly: dict[str, Any] | None = None
    for entry, draw, claim in rows:
        breakdown = entry.score_window if isinstance(entry.score_window, dict) else {}
        preview = draw.draw_numbers if isinstance(draw.draw_numbers, dict) else {}
        serialized_preview = _serialize_draw_preview(preview)
        user_visible_preview = serialized_preview
        if draw.status != "completed" and isinstance(user_visible_preview, dict):
            user_visible_preview = {
                **user_visible_preview,
                "numbers": [],
            }
        payout_cents = int((breakdown or {}).get("payout_cents") or 0)
        match_count = int((breakdown or {}).get("match_count") or entry.match_count or 0)
        can_submit_proof = bool(
            entry.is_winner
            and (
                claim is None
                or (
                    claim.review_status == "rejected"
                    and claim.payout_state != "paid"
                )
            )
        )
        item = {
            "entry_id": entry.id,
            "draw_id": draw.id,
            "draw_key": draw.month_key,
            "draw_kind": "monthly",
            "status": draw.status,
            "run_at": draw.run_at,
            "completed_at": draw.completed_at,
            "entry_numbers": _entry_pick_numbers(entry),
            "draw_numbers": list((user_visible_preview or {}).get("numbers") or []),
            "match_count": match_count,
            "match_label": _tier_label(match_count),
            "is_winner": bool(entry.is_winner),
            "verification_required": bool(entry.is_winner),
            "can_submit_proof": can_submit_proof,
            "payout_cents": payout_cents,
            "logic_mode": str((preview or {}).get("logic_mode") or "random"),
            "preview": user_visible_preview,
            "claim": {
                "claim_id": claim.id,
                "proof_url": claim.proof_url,
                "review_status": claim.review_status,
                "review_notes": claim.review_notes,
                "reviewed_by": claim.reviewed_by,
                "reviewed_at": claim.reviewed_at,
                "payout_state": claim.payout_state,
                "payout_reference": claim.payout_reference,
                "paid_at": claim.paid_at,
                "submitted_at": claim.created_at,
                "updated_at": claim.updated_at,
            }
            if claim
            else None,
            "breakdown": {
                "matched_numbers": list((breakdown or {}).get("matched_numbers") or []),
                "tier_label": str((breakdown or {}).get("tier_label") or _tier_label(match_count)),
                "scores": list((breakdown or {}).get("scores") or []),
            },
        }
        items.append(item)
        if latest_monthly is None:
            latest_monthly = item

    return {
        "items": items,
        "latest_weekly": None,
        "latest_monthly": latest_monthly,
        "algo_version": "monthly_match_draw_v2",
    }


@router.get("/admin/analytics/bootstrap")
async def admin_analytics_bootstrap(
    days: int = Query(default=30, ge=7, le=120),
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    now = utcnow()
    start_dt = now - timedelta(days=days - 1)
    start_day = start_dt.date()

    async def _safe_scalar(stmt: Any, *, default: Any = 0) -> Any:
        try:
            return (await db.execute(stmt)).scalar_one() or default
        except ProgrammingError as exc:
            if not _is_missing_relation_error(exc):
                raise
            await db.rollback()
            return default

    async def _safe_rows(stmt: Any) -> list[Any]:
        try:
            return (await db.execute(stmt)).all()
        except ProgrammingError as exc:
            if not _is_missing_relation_error(exc):
                raise
            await db.rollback()
            return []

    active_subs_stmt = select(func.count(GolfSubscription.id)).where(
        GolfSubscription.status == "active",
        GolfSubscription.current_period_end >= now,
    )
    active_subscribers = int(await _safe_scalar(active_subs_stmt, default=0))

    total_subs_stmt = select(func.count(GolfSubscription.id))
    total_subscriptions = int(await _safe_scalar(total_subs_stmt, default=0))

    subs_revenue_stmt = select(func.coalesce(func.sum(GolfSubscriptionPayment.amount_cents), 0))
    total_subscription_revenue_cents = int(await _safe_scalar(subs_revenue_stmt, default=0))

    charity_total_stmt = select(func.coalesce(func.sum(GolfCharityDonation.amount_cents), 0))
    total_charity_donations_cents = int(await _safe_scalar(charity_total_stmt, default=0))

    event_donation_total_stmt = select(
        func.coalesce(func.sum(TournamentEventDonation.amount_cents), 0)
    ).where(TournamentEventDonation.status == "completed")
    total_event_donations_cents = int(await _safe_scalar(event_donation_total_stmt, default=0))

    wallet_topups_stmt = select(func.coalesce(func.sum(WalletLedger.amount), 0.0)).where(
        WalletLedger.entry_type == "topup",
        WalletLedger.status == "completed",
    )
    total_wallet_topups_usd = float(await _safe_scalar(wallet_topups_stmt, default=0.0))

    draw_total_stmt = select(func.count(GolfDraw.id))
    total_draws = int(await _safe_scalar(draw_total_stmt, default=0))
    draw_completed_stmt = select(func.count(GolfDraw.id)).where(GolfDraw.status == "completed")
    completed_draws = int(await _safe_scalar(draw_completed_stmt, default=0))
    weekly_draws_stmt = select(func.count(GolfDraw.id)).where(GolfDraw.month_key.like("%-W%"))
    weekly_draws = int(await _safe_scalar(weekly_draws_stmt, default=0))
    monthly_draws = max(total_draws - weekly_draws, 0)
    winner_entries_stmt = select(func.count(GolfDrawEntry.id)).where(GolfDrawEntry.is_winner.is_(True))
    total_winner_entries = int(await _safe_scalar(winner_entries_stmt, default=0))

    pending_claims_stmt = select(func.count(GolfWinnerClaim.id)).where(GolfWinnerClaim.review_status == "pending")
    pending_claims = int(await _safe_scalar(pending_claims_stmt, default=0))
    paid_claims_stmt = select(func.count(GolfWinnerClaim.id)).where(GolfWinnerClaim.payout_state == "paid")
    paid_claims = int(await _safe_scalar(paid_claims_stmt, default=0))
    payout_pending_stmt = select(func.count(GolfWinnerClaim.id)).where(
        GolfWinnerClaim.review_status == "approved",
        GolfWinnerClaim.payout_state == "pending",
    )
    approved_pending_payouts = int(await _safe_scalar(payout_pending_stmt, default=0))

    role_counts_stmt = select(User.role, func.count(User.id)).group_by(User.role)
    role_counts = _status_count_map(await _safe_rows(role_counts_stmt))

    event_status_stmt = select(TournamentEvent.status, func.count(TournamentEvent.id)).group_by(
        TournamentEvent.status
    )
    event_status_counts = _status_count_map(await _safe_rows(event_status_stmt))

    session_status_stmt = select(
        TournamentChallengeSession.status,
        func.count(TournamentChallengeSession.id),
    ).group_by(TournamentChallengeSession.status)
    session_status_counts = _status_count_map(await _safe_rows(session_status_stmt))

    score_status_stmt = select(
        TournamentSessionScore.status,
        func.count(TournamentSessionScore.id),
    ).group_by(TournamentSessionScore.status)
    score_status_counts = _status_count_map(await _safe_rows(score_status_stmt))

    unlock_status_stmt = select(
        TournamentEventUnlock.status,
        func.count(TournamentEventUnlock.id),
    ).group_by(TournamentEventUnlock.status)
    unlock_status_counts = _status_count_map(await _safe_rows(unlock_status_stmt))

    fraud_severity_stmt = select(
        TournamentFraudFlag.severity,
        func.count(TournamentFraudFlag.id),
    ).group_by(TournamentFraudFlag.severity)
    fraud_severity_counts = _status_count_map(await _safe_rows(fraud_severity_stmt))
    open_fraud_stmt = select(func.count(TournamentFraudFlag.id)).where(TournamentFraudFlag.status == "open")
    open_fraud_flags = int(await _safe_scalar(open_fraud_stmt, default=0))

    pending_friend_requests_stmt = select(func.count(TournamentFriendRequest.id)).where(
        TournamentFriendRequest.status == "pending"
    )
    pending_friend_requests = int(await _safe_scalar(pending_friend_requests_stmt, default=0))

    unread_messages_stmt = select(func.count(TournamentInboxMessage.id)).where(
        TournamentInboxMessage.status == "unread"
    )
    unread_messages = int(await _safe_scalar(unread_messages_stmt, default=0))

    daily_subs_stmt = (
        select(
            func.date(GolfSubscriptionPayment.created_at).label("day"),
            func.coalesce(func.sum(GolfSubscriptionPayment.amount_cents), 0).label("value"),
        )
        .where(GolfSubscriptionPayment.created_at >= start_dt)
        .group_by(func.date(GolfSubscriptionPayment.created_at))
        .order_by(func.date(GolfSubscriptionPayment.created_at))
    )
    daily_subs_rows = await _safe_rows(daily_subs_stmt)

    daily_charity_stmt = (
        select(
            func.date(GolfCharityDonation.created_at).label("day"),
            func.coalesce(func.sum(GolfCharityDonation.amount_cents), 0).label("value"),
        )
        .where(GolfCharityDonation.created_at >= start_dt)
        .group_by(func.date(GolfCharityDonation.created_at))
        .order_by(func.date(GolfCharityDonation.created_at))
    )
    daily_charity_rows = await _safe_rows(daily_charity_stmt)

    daily_event_donations_stmt = (
        select(
            func.date(TournamentEventDonation.created_at).label("day"),
            func.coalesce(func.sum(TournamentEventDonation.amount_cents), 0).label("value"),
        )
        .where(
            TournamentEventDonation.created_at >= start_dt,
            TournamentEventDonation.status == "completed",
        )
        .group_by(func.date(TournamentEventDonation.created_at))
        .order_by(func.date(TournamentEventDonation.created_at))
    )
    daily_event_donations_rows = await _safe_rows(daily_event_donations_stmt)

    daily_draws_completed_stmt = (
        select(
            func.date(GolfDraw.completed_at).label("day"),
            func.count(GolfDraw.id).label("value"),
        )
        .where(
            GolfDraw.completed_at.is_not(None),
            GolfDraw.completed_at >= start_dt,
        )
        .group_by(func.date(GolfDraw.completed_at))
        .order_by(func.date(GolfDraw.completed_at))
    )
    daily_draws_completed_rows = await _safe_rows(daily_draws_completed_stmt)

    return {
        "window": {
            "days": days,
            "start_at": datetime.combine(start_day, datetime.min.time(), tzinfo=timezone.utc),
            "end_at": now,
        },
        "kpis": {
            "financial": {
                "active_subscribers": active_subscribers,
                "total_subscriptions": total_subscriptions,
                "subscription_revenue_cents": total_subscription_revenue_cents,
                "charity_donations_cents": total_charity_donations_cents,
                "event_donations_cents": total_event_donations_cents,
                "wallet_topups_usd": round(total_wallet_topups_usd, 2),
            },
            "draws": {
                "total_draws": total_draws,
                "completed_draws": completed_draws,
                "weekly_draws": weekly_draws,
                "monthly_draws": monthly_draws,
                "winner_entries": total_winner_entries,
                "pending_claims": pending_claims,
                "approved_pending_payouts": approved_pending_payouts,
                "paid_claims": paid_claims,
            },
            "engagement": {
                "events_active": event_status_counts.get("active", 0),
                "sessions_in_progress": session_status_counts.get("in_progress", 0),
                "scores_pending_confirmation": score_status_counts.get("pending_confirmation", 0),
                "event_unlocks_active": unlock_status_counts.get("active", 0),
                "pending_friend_requests": pending_friend_requests,
                "unread_inbox_messages": unread_messages,
            },
            "integrity": {
                "open_fraud_flags": open_fraud_flags,
                "high_severity_flags": fraud_severity_counts.get("high", 0),
                "medium_severity_flags": fraud_severity_counts.get("medium", 0),
            },
            "roles": role_counts,
        },
        "breakdowns": {
            "event_status": event_status_counts,
            "session_status": session_status_counts,
            "score_status": score_status_counts,
            "unlock_status": unlock_status_counts,
            "fraud_severity": fraud_severity_counts,
        },
        "trends": {
            "subscription_revenue_cents_daily": _dense_daily_series(start_day, days, daily_subs_rows),
            "charity_donations_cents_daily": _dense_daily_series(start_day, days, daily_charity_rows),
            "event_donations_cents_daily": _dense_daily_series(start_day, days, daily_event_donations_rows),
            "draws_completed_daily": _dense_daily_series(start_day, days, daily_draws_completed_rows),
        },
    }


async def _get_monthly_draw_or_404(db: AsyncSession, draw_id: str) -> GolfDraw:
    draw = (await db.execute(select(GolfDraw).where(GolfDraw.id == draw_id))).scalar_one_or_none()
    if not draw:
        raise HTTPException(status_code=404, detail="Draw not found")
    if not _is_monthly_draw(draw.month_key):
        raise HTTPException(status_code=410, detail="Legacy weekly draws are no longer supported")
    return draw


async def _monthly_draw_entries(db: AsyncSession, draw_id: str) -> list[GolfDrawEntry]:
    return (
        await db.execute(
            select(GolfDrawEntry)
            .where(GolfDrawEntry.draw_id == draw_id)
            .order_by(GolfDrawEntry.created_at.asc(), GolfDrawEntry.id.asc())
        )
    ).scalars().all()


async def _simulate_draw_preview(
    *,
    draw: GolfDraw,
    payload: DrawRunRequest,
    db: AsyncSession,
) -> dict[str, Any]:
    if draw.status == "completed":
        raise HTTPException(status_code=409, detail="Draw already published")

    settings_row = await _get_or_create_draw_settings(db)
    settings_payload = _serialize_draw_settings(settings_row)
    entries = await _monthly_draw_entries(db, draw.id)
    min_entries_required = int(settings_payload.get("monthly_min_events_required") or 1)
    if len(entries) < min_entries_required:
        raise HTTPException(
            status_code=409,
            detail=f"At least {min_entries_required} entries are required before simulating this draw",
        )

    logic_mode = _draw_logic_mode(payload.logic_mode)
    seed = (payload.draw_seed or "").strip() or secrets.token_hex(16)
    frequency_analysis: dict[str, Any] | None = None
    if payload.force_numbers:
        draw_numbers = _normalize_draw_numbers(payload.force_numbers)
    elif logic_mode == "algorithmic":
        algorithmic_plan = _build_algorithmic_number_plan(entries, seed=seed)
        draw_numbers = _normalize_draw_numbers(algorithmic_plan["numbers"])
        frequency_analysis = {
            "hot_numbers": algorithmic_plan["hot_numbers"],
            "cold_numbers": algorithmic_plan["cold_numbers"],
            "frequency_map": algorithmic_plan["frequency_map"],
        }
    else:
        draw_numbers = generate_draw_numbers(seed)

    simulated_at = utcnow()
    pool_breakdown = await _active_subscription_pool_snapshot(
        db,
        as_of=simulated_at,
        jackpot_carry_in_cents=int(draw.jackpot_carry_in_cents or 0),
    )
    evaluation = _evaluate_monthly_draw(
        draw=draw,
        entries=entries,
        draw_numbers=draw_numbers,
        logic_mode=logic_mode,
        pool_breakdown=pool_breakdown,
        seed=seed,
        simulated_at=simulated_at,
    )

    preview_payload = {
        "preview_only": True,
        "logic_mode": logic_mode,
        "seed": seed,
        "numbers": evaluation["numbers"],
        "simulated_at": simulated_at.isoformat(),
        "entry_count": evaluation["entry_count"],
        "winner_count": evaluation["winner_count"],
        "jackpot_won": evaluation["jackpot_won"],
        "rollover_cents": evaluation["rollover_cents"],
        "pool_total_cents": evaluation["pool_total_cents"],
        "total_prize_exposure_cents": evaluation["total_prize_exposure_cents"],
        "total_awarded_cents": evaluation["total_awarded_cents"],
        "tier_summary": evaluation["tier_summary"],
        "pool_breakdown": pool_breakdown,
        "frequency_analysis": frequency_analysis,
    }

    draw.status = "closed"
    draw.run_at = simulated_at
    draw.draw_seed = seed
    draw.draw_numbers = preview_payload
    draw.pool_total_cents = int(pool_breakdown.get("pool_total_cents") or 0)
    draw.match5_pool_cents = int(
        (((pool_breakdown.get("tier_summary") or {}).get("match_5") or {}).get("pool_cents")) or 0
    )
    draw.match4_pool_cents = int(
        (((pool_breakdown.get("tier_summary") or {}).get("match_4") or {}).get("pool_cents")) or 0
    )
    draw.match3_pool_cents = int(
        (((pool_breakdown.get("tier_summary") or {}).get("match_3") or {}).get("pool_cents")) or 0
    )
    await db.commit()
    await db.refresh(draw)
    return preview_payload


async def _publish_draw_results(
    *,
    draw: GolfDraw,
    current_user: User,
    db: AsyncSession,
) -> dict[str, Any]:
    if draw.status == "completed":
        raise HTTPException(status_code=409, detail="Draw already published")

    preview_payload = draw.draw_numbers if isinstance(draw.draw_numbers, dict) else {}
    preview_numbers = preview_payload.get("numbers")
    if not isinstance(preview_numbers, list):
        raise HTTPException(status_code=409, detail="Simulate this draw before publishing results")

    entries = await _monthly_draw_entries(db, draw.id)
    simulated_at = draw.run_at or utcnow()
    logic_mode = _draw_logic_mode(str(preview_payload.get("logic_mode") or "random"))
    seed = str(preview_payload.get("seed") or draw.draw_seed or secrets.token_hex(16))
    pool_breakdown = (
        preview_payload.get("pool_breakdown")
        if isinstance(preview_payload.get("pool_breakdown"), dict)
        else {}
    )
    if not pool_breakdown:
        pool_breakdown = await _active_subscription_pool_snapshot(
            db,
            as_of=simulated_at,
            jackpot_carry_in_cents=int(draw.jackpot_carry_in_cents or 0),
        )
    evaluation = _evaluate_monthly_draw(
        draw=draw,
        entries=entries,
        draw_numbers=preview_numbers,
        logic_mode=logic_mode,
        pool_breakdown=pool_breakdown,
        seed=seed,
        simulated_at=simulated_at,
    )
    result_by_entry_id = {
        str(item["entry_id"]): item for item in evaluation["entry_results"]
    }
    published_at = utcnow()
    numbers_text = ", ".join(str(number) for number in evaluation["numbers"])

    for entry in entries:
        result = result_by_entry_id.get(str(entry.id))
        if not result:
            continue
        entry.match_count = int(result["match_count"])
        entry.is_winner = bool(result["is_winner"])
        entry.score_window = {
            "scores": result["score_values"],
            "entry_numbers": result["entry_numbers"],
            "draw_numbers": evaluation["numbers"],
            "matched_numbers": result["matched_numbers"],
            "match_count": int(result["match_count"]),
            "tier_label": result["tier_label"],
            "payout_cents": int(result["payout_cents"]),
            "logic_mode": logic_mode,
            "seed": seed,
            "simulated_at": simulated_at.isoformat(),
            "published_at": published_at.isoformat(),
        }

        message = (
            f"Monthly draw numbers: {numbers_text}. "
            f"You matched {int(result['match_count'])} number(s). "
        )
        if int(result["payout_cents"]) > 0:
            message += f"You won ${format(int(result['payout_cents']) / 100.0, '.2f')}."
        elif int(result["match_count"]) >= 3:
            message += "This tier had no cash award after split rules."
        else:
            message += "Keep playing for next month's draw."
        if int(evaluation["rollover_cents"]) > 0:
            message += f" Jackpot rolls over ${format(int(evaluation['rollover_cents']) / 100.0, '.2f')}."

        db.add(
            TournamentInboxMessage(
                recipient_user_id=int(entry.user_id),
                sender_user_id=current_user.id,
                message_type="system",
                title="Monthly Draw Results Published",
                body=message,
                status="unread",
            )
        )

    if int(evaluation["rollover_cents"]) > 0:
        db.add(
            GolfPrizeRollover(
                from_draw_id=draw.id,
                amount_cents=int(evaluation["rollover_cents"]),
                reason="no_5_match_winner",
            )
        )

    draw.status = "completed"
    draw.completed_at = published_at
    draw.draw_seed = seed
    draw.pool_total_cents = int(pool_breakdown.get("pool_total_cents") or 0)
    draw.match5_pool_cents = int(
        (((pool_breakdown.get("tier_summary") or {}).get("match_5") or {}).get("pool_cents")) or 0
    )
    draw.match4_pool_cents = int(
        (((pool_breakdown.get("tier_summary") or {}).get("match_4") or {}).get("pool_cents")) or 0
    )
    draw.match3_pool_cents = int(
        (((pool_breakdown.get("tier_summary") or {}).get("match_3") or {}).get("pool_cents")) or 0
    )
    draw.draw_numbers = {
        **preview_payload,
        "preview_only": False,
        "published_at": published_at.isoformat(),
        "numbers": evaluation["numbers"],
        "winner_count": evaluation["winner_count"],
        "rollover_cents": evaluation["rollover_cents"],
        "jackpot_won": evaluation["jackpot_won"],
        "pool_total_cents": evaluation["pool_total_cents"],
        "total_prize_exposure_cents": evaluation["total_prize_exposure_cents"],
        "total_awarded_cents": evaluation["total_awarded_cents"],
        "tier_summary": evaluation["tier_summary"],
        "pool_breakdown": pool_breakdown,
        "published_by_user_id": current_user.id,
    }
    await db.commit()
    await db.refresh(draw)

    return {
        "draw_id": draw.id,
        "month_key": draw.month_key,
        "status": draw.status,
        "logic_mode": logic_mode,
        "numbers": evaluation["numbers"],
        "winner_count": evaluation["winner_count"],
        "tier_summary": evaluation["tier_summary"],
        "pool_breakdown": pool_breakdown,
        "rollover_cents": evaluation["rollover_cents"],
        "published_at": published_at,
    }


@router.get("/admin/draw-settings")
async def admin_get_draw_settings(
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    settings_row = await _get_or_create_draw_settings(db)
    return {"settings": _serialize_draw_settings(settings_row)}


@router.put("/admin/draw-settings")
async def admin_update_draw_settings(
    payload: DrawSettingsUpdateRequest,
    current_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    _validate_draw_settings_values(
        weekly_prize_cents=payload.weekly_prize_cents,
        monthly_first_prize_cents=payload.monthly_first_prize_cents,
        monthly_second_prize_cents=payload.monthly_second_prize_cents,
        monthly_third_prize_cents=payload.monthly_third_prize_cents,
        monthly_min_events_required=payload.monthly_min_events_required,
    )
    settings_row = await _get_or_create_draw_settings(db)
    settings_row.weekly_prize_cents = int(payload.weekly_prize_cents)
    settings_row.monthly_first_prize_cents = int(payload.monthly_first_prize_cents)
    settings_row.monthly_second_prize_cents = int(payload.monthly_second_prize_cents)
    settings_row.monthly_third_prize_cents = int(payload.monthly_third_prize_cents)
    settings_row.monthly_min_events_required = int(payload.monthly_min_events_required)
    settings_row.updated_by = current_user.id
    await db.commit()
    await db.refresh(settings_row)
    return {"settings": _serialize_draw_settings(settings_row)}


@router.get("/admin/draws")
async def admin_list_draws(
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    settings_row = await _get_or_create_draw_settings(db)
    settings_payload = _serialize_draw_settings(settings_row)
    draws_stmt = (
        select(GolfDraw)
        .where(~GolfDraw.month_key.like("%-W%"))
        .order_by(GolfDraw.month_key.desc(), GolfDraw.created_at.desc())
    )
    draws = (await db.execute(draws_stmt)).scalars().all()
    if not draws:
        return {"draws": [], "settings": settings_payload}

    draw_ids = [d.id for d in draws]
    entries_counts_stmt = (
        select(GolfDrawEntry.draw_id, func.count(GolfDrawEntry.id))
        .where(GolfDrawEntry.draw_id.in_(draw_ids))
        .group_by(GolfDrawEntry.draw_id)
    )
    winner_counts_stmt = (
        select(GolfDrawEntry.draw_id, func.count(GolfDrawEntry.id))
        .where(
            GolfDrawEntry.draw_id.in_(draw_ids),
            GolfDrawEntry.is_winner.is_(True),
        )
        .group_by(GolfDrawEntry.draw_id)
    )
    entries_counts = {
        str(draw_id): int(count or 0)
        for draw_id, count in (await db.execute(entries_counts_stmt)).all()
    }
    winner_counts = {
        str(draw_id): int(count or 0)
        for draw_id, count in (await db.execute(winner_counts_stmt)).all()
    }

    draw_items: list[dict[str, Any]] = []
    now = utcnow()
    for draw in draws:
        preview = _serialize_draw_preview(draw.draw_numbers if isinstance(draw.draw_numbers, dict) else None)
        pool_breakdown = (preview or {}).get("pool_breakdown")
        if not isinstance(pool_breakdown, dict):
            pool_breakdown = await _active_subscription_pool_snapshot(
                db,
                as_of=draw.run_at or now,
                jackpot_carry_in_cents=int(draw.jackpot_carry_in_cents or 0),
            )
        draw_items.append(
            {
                "id": draw.id,
                "month_key": draw.month_key,
                "draw_kind": "monthly",
                "status": draw.status,
                "pool_total_cents": int((pool_breakdown or {}).get("pool_total_cents") or 0),
                "jackpot_carry_in_cents": int(draw.jackpot_carry_in_cents or 0),
                "run_at": draw.run_at,
                "completed_at": draw.completed_at,
                "created_at": draw.created_at,
                "entries_count": entries_counts.get(draw.id, 0),
                "winner_count": winner_counts.get(draw.id, 0),
                "preview": preview,
                "pool_breakdown": pool_breakdown,
                "active_subscriber_count": int((pool_breakdown or {}).get("active_subscriber_count") or 0),
            }
        )

    return {
        "settings": settings_payload,
        "draws": draw_items,
    }


@router.post("/admin/draws", status_code=status.HTTP_201_CREATED)
async def admin_create_draw(
    payload: DrawCreateRequest,
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    if not _is_monthly_draw(payload.month_key):
        raise HTTPException(status_code=422, detail="Only monthly draws are supported")
    exists_stmt = select(GolfDraw).where(GolfDraw.month_key == payload.month_key)
    exists = (await db.execute(exists_stmt)).scalar_one_or_none()
    if exists:
        raise HTTPException(status_code=409, detail="Draw for this month already exists")

    prior_draw = (
        await db.execute(
            select(GolfDraw)
            .where(
                GolfDraw.status == "completed",
                GolfDraw.month_key < payload.month_key,
                ~GolfDraw.month_key.like("%-W%"),
            )
            .order_by(GolfDraw.month_key.desc(), GolfDraw.completed_at.desc().nullslast())
            .limit(1)
        )
    ).scalar_one_or_none()
    prior_preview = prior_draw.draw_numbers if prior_draw and isinstance(prior_draw.draw_numbers, dict) else {}
    derived_carry_in = int((prior_preview or {}).get("rollover_cents") or 0)
    carry_in_cents = int(payload.jackpot_carry_in_cents or derived_carry_in)

    draw = GolfDraw(
        month_key=payload.month_key,
        status="open",
        jackpot_carry_in_cents=carry_in_cents,
    )
    db.add(draw)
    await db.commit()
    await db.refresh(draw)
    return {
        "id": draw.id,
        "month_key": draw.month_key,
        "status": draw.status,
        "jackpot_carry_in_cents": int(draw.jackpot_carry_in_cents or 0),
    }


@router.post("/admin/draws/{draw_id}/simulate")
async def admin_simulate_draw(
    draw_id: str,
    payload: DrawRunRequest,
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    draw = await _get_monthly_draw_or_404(db, draw_id)
    preview = await _simulate_draw_preview(draw=draw, payload=payload, db=db)
    return {
        "draw_id": draw.id,
        "month_key": draw.month_key,
        "status": draw.status,
        "preview": _serialize_draw_preview(preview),
    }


@router.post("/admin/draws/{draw_id}/publish")
async def admin_publish_draw(
    draw_id: str,
    current_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    draw = await _get_monthly_draw_or_404(db, draw_id)
    return await _publish_draw_results(draw=draw, current_user=current_user, db=db)


@router.post("/admin/draws/{draw_id}/run")
async def admin_run_draw(
    draw_id: str,
    payload: DrawRunRequest,
    current_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    draw = await _get_monthly_draw_or_404(db, draw_id)
    if draw.status != "closed" or not isinstance(draw.draw_numbers, dict):
        await _simulate_draw_preview(draw=draw, payload=payload, db=db)
        await db.refresh(draw)
    return await _publish_draw_results(draw=draw, current_user=current_user, db=db)


@router.get("/admin/draws/{draw_id}/results")
async def admin_draw_results(
    draw_id: str,
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    draw = await _get_monthly_draw_or_404(db, draw_id)
    preview_payload = draw.draw_numbers if isinstance(draw.draw_numbers, dict) else {}
    serialized_preview = _serialize_draw_preview(preview_payload)
    pool_breakdown = (
        serialized_preview.get("pool_breakdown")
        if isinstance(serialized_preview, dict)
        else None
    )
    if not isinstance(pool_breakdown, dict):
        pool_breakdown = await _active_subscription_pool_snapshot(
            db,
            as_of=draw.run_at or utcnow(),
            jackpot_carry_in_cents=int(draw.jackpot_carry_in_cents or 0),
        )
    entries = await _monthly_draw_entries(db, draw_id)
    users = (
        await db.execute(select(User).where(User.id.in_([int(entry.user_id) for entry in entries])))
    ).scalars().all() if entries else []
    user_by_id = {int(user.id): user for user in users}

    live_results: dict[str, dict[str, Any]] = {}
    if isinstance(preview_payload.get("numbers"), list):
        settings_row = await _get_or_create_draw_settings(db)
        settings_payload = _serialize_draw_settings(settings_row)
        simulated_at = draw.run_at or utcnow()
        evaluation = _evaluate_monthly_draw(
            draw=draw,
            entries=entries,
            draw_numbers=preview_payload.get("numbers"),
            logic_mode=_draw_logic_mode(str(preview_payload.get("logic_mode") or "random")),
            settings_payload=settings_payload,
            seed=str(preview_payload.get("seed") or draw.draw_seed or secrets.token_hex(16)),
            simulated_at=simulated_at,
        )
        live_results = {
            str(item["entry_id"]): item for item in evaluation["entry_results"]
        }

    return {
        "draw": {
            "id": draw.id,
            "month_key": draw.month_key,
            "status": draw.status,
            "draw_kind": "monthly",
            "preview": serialized_preview,
            "pool_total_cents": int((pool_breakdown or {}).get("pool_total_cents") or 0),
            "match5_pool_cents": draw.match5_pool_cents,
            "match4_pool_cents": draw.match4_pool_cents,
            "match3_pool_cents": draw.match3_pool_cents,
            "jackpot_carry_in_cents": int(draw.jackpot_carry_in_cents or 0),
            "pool_breakdown": pool_breakdown,
        },
        "entries": [
            {
                "id": e.id,
                "user_id": e.user_id,
                "username": (user_by_id.get(int(e.user_id)).username if user_by_id.get(int(e.user_id)) else None),
                "email": (user_by_id.get(int(e.user_id)).email if user_by_id.get(int(e.user_id)) else None),
                "numbers": _entry_pick_numbers(e),
                "match_count": int(
                    (live_results.get(str(e.id), {}).get("match_count"))
                    if str(e.id) in live_results
                    else (e.match_count or 0)
                ),
                "matched_numbers": live_results.get(str(e.id), {}).get("matched_numbers", []),
                "payout_cents": int(live_results.get(str(e.id), {}).get("payout_cents") or 0),
                "is_winner": bool(
                    (live_results.get(str(e.id), {}).get("is_winner"))
                    if str(e.id) in live_results
                    else e.is_winner
                ),
            }
            for e in entries
        ],
    }


@router.get("/admin/winners")
async def admin_full_winners_list(
    limit: int = Query(default=300, ge=1, le=2000),
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = (
        select(GolfDrawEntry, GolfDraw, User, GolfWinnerClaim)
        .join(GolfDraw, GolfDraw.id == GolfDrawEntry.draw_id)
        .join(User, User.id == GolfDrawEntry.user_id)
        .outerjoin(GolfWinnerClaim, GolfWinnerClaim.draw_entry_id == GolfDrawEntry.id)
        .where(
            GolfDrawEntry.is_winner.is_(True),
            ~GolfDraw.month_key.like("%-W%"),
        )
        .order_by(GolfDraw.completed_at.desc().nullslast(), GolfDrawEntry.created_at.desc())
        .limit(limit)
    )
    rows = (await db.execute(stmt)).all()
    return {
        "items": [
            {
                "entry_id": entry.id,
                "draw_id": draw.id,
                "draw_key": draw.month_key,
                "draw_kind": "monthly",
                "draw_status": draw.status,
                "draw_completed_at": draw.completed_at,
                "user_id": user.id,
                "username": user.username,
                "email": user.email,
                "numbers": entry.numbers,
                "match_count": entry.match_count,
                "tier_label": _tier_label(int(entry.match_count or 0)),
                "payout_cents": int(
                    ((entry.score_window or {}).get("payout_cents"))
                    if isinstance(entry.score_window, dict)
                    else 0
                ),
                "claimed": claim is not None,
                "claim_id": claim.id if claim else None,
                "review_status": claim.review_status if claim else None,
                "payout_state": claim.payout_state if claim else None,
                "paid_at": claim.paid_at if claim else None,
            }
            for entry, draw, user, claim in rows
        ]
    }


@router.post("/admin/draws/run-fair")
async def admin_run_fair_draw(
    payload: FairDrawRunRequest,
    current_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    if payload.draw_kind == "weekly":
        raise HTTPException(status_code=410, detail="Weekly draws have been retired")
    cutoff = payload.cutoff_at or utcnow()
    draw_key = _draw_key_for(payload.draw_kind, cutoff)
    draw = (await db.execute(select(GolfDraw).where(GolfDraw.month_key == draw_key))).scalar_one_or_none()
    if not draw:
        prior_draw = (
            await db.execute(
                select(GolfDraw)
                .where(
                    GolfDraw.status == "completed",
                    GolfDraw.month_key < draw_key,
                    ~GolfDraw.month_key.like("%-W%"),
                )
                .order_by(GolfDraw.month_key.desc(), GolfDraw.completed_at.desc().nullslast())
                .limit(1)
            )
        ).scalar_one_or_none()
        prior_preview = prior_draw.draw_numbers if prior_draw and isinstance(prior_draw.draw_numbers, dict) else {}
        draw = GolfDraw(
            month_key=draw_key,
            status="open",
            jackpot_carry_in_cents=int((prior_preview or {}).get("rollover_cents") or 0),
        )
        db.add(draw)
        await db.commit()
        await db.refresh(draw)
    if draw.status == "completed":
        raise HTTPException(status_code=409, detail="Draw already completed for this period")
    if draw.status != "closed" or not isinstance(draw.draw_numbers, dict):
        await _simulate_draw_preview(
            draw=draw,
            payload=DrawRunRequest(logic_mode="algorithmic"),
            db=db,
        )
        await db.refresh(draw)
    return await _publish_draw_results(draw=draw, current_user=current_user, db=db)


@router.post("/me/winner-claims/{entry_id}", status_code=status.HTTP_201_CREATED)
async def create_winner_claim(
    entry_id: str,
    payload: WinnerClaimCreateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    entry_stmt = select(GolfDrawEntry).where(
        and_(
            GolfDrawEntry.id == entry_id,
            GolfDrawEntry.user_id == current_user.id,
            GolfDrawEntry.is_winner.is_(True),
        )
    )
    entry = (await db.execute(entry_stmt)).scalar_one_or_none()
    if not entry:
        raise HTTPException(status_code=404, detail="Winning entry not found")

    existing_stmt = select(GolfWinnerClaim).where(GolfWinnerClaim.draw_entry_id == entry_id)
    existing = (await db.execute(existing_stmt)).scalar_one_or_none()
    if existing:
        if existing.payout_state == "paid":
            raise HTTPException(status_code=409, detail="Claim has already been paid")
        if existing.review_status != "rejected":
            raise HTTPException(status_code=409, detail="Claim already submitted for this winning entry")
        existing.proof_url = str(payload.proof_url)
        existing.review_status = "pending"
        existing.review_notes = None
        existing.reviewed_by = None
        existing.reviewed_at = None
        existing.payout_state = "pending"
        existing.payout_reference = None
        existing.paid_at = None
        await db.commit()
        await db.refresh(existing)
        return {
            "claim_id": existing.id,
            "review_status": existing.review_status,
            "payout_state": existing.payout_state,
            "resubmitted": True,
        }

    claim = GolfWinnerClaim(
        draw_entry_id=entry_id,
        user_id=current_user.id,
        proof_url=str(payload.proof_url),
        review_status="pending",
        payout_state="pending",
    )
    db.add(claim)
    await db.commit()
    await db.refresh(claim)

    return {
        "claim_id": claim.id,
        "review_status": claim.review_status,
        "payout_state": claim.payout_state,
        "resubmitted": False,
    }


@router.get("/admin/winner-claims")
async def admin_list_winner_claims(
    review_status_filter: str | None = Query(default=None, alias="review_status"),
    payout_state_filter: str | None = Query(default=None, alias="payout_state"),
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = (
        select(GolfWinnerClaim, GolfDrawEntry, GolfDraw, User)
        .join(GolfDrawEntry, GolfDrawEntry.id == GolfWinnerClaim.draw_entry_id)
        .join(GolfDraw, GolfDraw.id == GolfDrawEntry.draw_id)
        .join(User, User.id == GolfWinnerClaim.user_id)
        .where(~GolfDraw.month_key.like("%-W%"))
        .order_by(GolfWinnerClaim.updated_at.desc(), GolfWinnerClaim.created_at.desc())
    )

    if review_status_filter:
        stmt = stmt.where(GolfWinnerClaim.review_status == review_status_filter)
    if payout_state_filter:
        stmt = stmt.where(GolfWinnerClaim.payout_state == payout_state_filter)

    claims = (await db.execute(stmt)).all()
    return {
        "claims": [
            {
                "id": c.id,
                "draw_entry_id": c.draw_entry_id,
                "user_id": c.user_id,
                "username": user.username,
                "email": user.email,
                "draw_id": draw.id,
                "draw_key": draw.month_key,
                "draw_status": draw.status,
                "match_count": int(entry.match_count or 0),
                "tier_label": _tier_label(int(entry.match_count or 0)),
                "entry_numbers": _entry_pick_numbers(entry),
                "payout_cents": int(
                    ((entry.score_window or {}).get("payout_cents"))
                    if isinstance(entry.score_window, dict)
                    else 0
                ),
                "proof_url": c.proof_url,
                "review_status": c.review_status,
                "review_notes": c.review_notes,
                "reviewed_by": c.reviewed_by,
                "reviewed_at": c.reviewed_at,
                "payout_state": c.payout_state,
                "payout_reference": c.payout_reference,
                "paid_at": c.paid_at,
                "created_at": c.created_at,
                "updated_at": c.updated_at,
            }
            for c, entry, draw, user in claims
        ]
    }


@router.post("/admin/winner-claims/{claim_id}/review")
async def admin_review_winner_claim(
    claim_id: str,
    payload: WinnerClaimReviewRequest,
    current_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = select(GolfWinnerClaim).where(GolfWinnerClaim.id == claim_id)
    claim = (await db.execute(stmt)).scalar_one_or_none()
    if not claim:
        raise HTTPException(status_code=404, detail="Winner claim not found")

    claim.review_status = "approved" if payload.action == "approve" else "rejected"
    claim.review_notes = (payload.review_notes or "").strip() or None
    claim.reviewed_by = current_user.id
    claim.reviewed_at = utcnow()

    await db.commit()

    return {
        "claim_id": claim.id,
        "review_status": claim.review_status,
        "reviewed_by": claim.reviewed_by,
        "reviewed_at": claim.reviewed_at,
    }


@router.post("/admin/winner-claims/{claim_id}/mark-paid")
async def admin_mark_claim_paid(
    claim_id: str,
    payload: MarkPaidRequest,
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    stmt = select(GolfWinnerClaim).where(GolfWinnerClaim.id == claim_id)
    claim = (await db.execute(stmt)).scalar_one_or_none()
    if not claim:
        raise HTTPException(status_code=404, detail="Winner claim not found")

    if claim.review_status != "approved":
        raise HTTPException(status_code=409, detail="Claim must be approved before payout")

    claim.payout_state = "paid"
    claim.payout_reference = payload.payout_reference
    claim.paid_at = utcnow()
    await db.commit()

    return {
        "claim_id": claim.id,
        "payout_state": claim.payout_state,
        "payout_reference": claim.payout_reference,
        "paid_at": claim.paid_at,
    }


@router.get("/admin/reports/summary")
async def admin_summary_report(
    _: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    total_users_stmt = select(func.count(User.id))
    total_users = int((await db.execute(total_users_stmt)).scalar_one() or 0)

    active_subs_stmt = select(func.count(GolfSubscription.id)).where(
        GolfSubscription.status == "active",
        GolfSubscription.current_period_end >= utcnow(),
    )
    active_subscribers = int((await db.execute(active_subs_stmt)).scalar_one() or 0)

    draw_pool_stmt = select(func.coalesce(func.sum(GolfDraw.pool_total_cents), 0))
    total_draw_pool = int((await db.execute(draw_pool_stmt)).scalar_one() or 0)

    payouts_stmt = select(func.count(GolfWinnerClaim.id)).where(GolfWinnerClaim.payout_state == "paid")
    paid_claims = int((await db.execute(payouts_stmt)).scalar_one() or 0)

    pending_review_stmt = select(func.count(GolfWinnerClaim.id)).where(GolfWinnerClaim.review_status == "pending")
    pending_review = int((await db.execute(pending_review_stmt)).scalar_one() or 0)

    total_draws_stmt = select(func.count(GolfDraw.id))
    total_draws = int((await db.execute(total_draws_stmt)).scalar_one() or 0)

    completed_draws_stmt = select(func.count(GolfDraw.id)).where(GolfDraw.status == "completed")
    completed_draws = int((await db.execute(completed_draws_stmt)).scalar_one() or 0)

    weekly_draws_stmt = select(func.count(GolfDraw.id)).where(GolfDraw.month_key.like("%-W%"))
    weekly_draws = int((await db.execute(weekly_draws_stmt)).scalar_one() or 0)
    monthly_draws = max(total_draws - weekly_draws, 0)

    winner_entries_stmt = select(func.count(GolfDrawEntry.id)).where(GolfDrawEntry.is_winner.is_(True))
    winner_entries = int((await db.execute(winner_entries_stmt)).scalar_one() or 0)

    return {
        "total_users": total_users,
        "active_subscribers": active_subscribers,
        "total_draw_pool_cents": total_draw_pool,
        "total_prize_pool_cents": total_draw_pool,
        "paid_claims": paid_claims,
        "pending_review_claims": pending_review,
        "draw_statistics": {
            "total_draws": total_draws,
            "completed_draws": completed_draws,
            "weekly_draws": weekly_draws,
            "monthly_draws": monthly_draws,
            "winner_entries": winner_entries,
        },
    }
