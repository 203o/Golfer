from datetime import date, datetime
from decimal import Decimal
import uuid

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Column,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    Index,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import declarative_base
from sqlalchemy.sql import func

BaseGolf = declarative_base()


class GolfCharity(BaseGolf):
    __tablename__ = "golf_charities"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    name = Column(String(160), nullable=False, unique=True)
    slug = Column(String(180), nullable=False, unique=True)
    description = Column(Text, nullable=True)
    cause = Column(String(80), nullable=True, index=True)
    location = Column(String(120), nullable=True)
    website_url = Column(String(300), nullable=True)
    hero_image_url = Column(String(500), nullable=True)
    gallery_image_urls = Column(JSONB, nullable=True)
    upcoming_events = Column(JSONB, nullable=True)
    spotlight_text = Column(Text, nullable=True)
    is_featured = Column(Boolean, nullable=False, default=False, index=True)
    is_active = Column(Boolean, nullable=False, default=True)
    total_raised_cents = Column(BigInteger, nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())


class GolfSubscriptionPlan(BaseGolf):
    __tablename__ = "golf_subscription_plans"

    id = Column(String(32), primary_key=True)
    name = Column(String(80), nullable=False)
    interval = Column(String(16), nullable=False)
    amount_cents = Column(Integer, nullable=False)
    currency = Column(String(8), nullable=False, default="USD")
    discount_pct = Column(Numeric(5, 2), nullable=False, default=0)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())

    __table_args__ = (
        CheckConstraint("interval in ('monthly','yearly')", name="ck_golf_plan_interval"),
    )


class GolfSubscription(BaseGolf):
    __tablename__ = "golf_subscriptions"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(Integer, nullable=False, index=True)
    plan_id = Column(String(32), nullable=False, index=True)
    status = Column(String(24), nullable=False, default="active", index=True)
    started_at = Column(DateTime(timezone=True), nullable=False)
    current_period_start = Column(DateTime(timezone=True), nullable=False)
    current_period_end = Column(DateTime(timezone=True), nullable=False, index=True)
    renewal_date = Column(DateTime(timezone=True), nullable=False, index=True)
    cancel_at_period_end = Column(Boolean, nullable=False, default=False)
    cancelled_at = Column(DateTime(timezone=True), nullable=True)
    lapsed_at = Column(DateTime(timezone=True), nullable=True)
    payment_provider = Column(String(32), nullable=False, default="stripe")
    payment_customer_id = Column(String(128), nullable=True)
    payment_subscription_id = Column(String(128), nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        CheckConstraint(
            "status in ('active','inactive','cancelled','lapsed')",
            name="ck_golf_subscription_status",
        ),
    )


class GolfSubscriptionPayment(BaseGolf):
    __tablename__ = "golf_subscription_payments"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(Integer, nullable=False, index=True)
    subscription_id = Column(String(36), nullable=False, index=True)
    plan_id = Column(String(32), nullable=False, index=True)
    amount_cents = Column(BigInteger, nullable=False)
    currency = Column(String(8), nullable=False, default="USD")
    payment_provider = Column(String(32), nullable=False, default="stripe")
    payment_reference = Column(String(128), nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())

    __table_args__ = (
        CheckConstraint("amount_cents > 0", name="ck_golf_subscription_payment_amount"),
    )


class GolfCharityDonation(BaseGolf):
    __tablename__ = "golf_charity_donations"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(Integer, nullable=False, index=True)
    charity_id = Column(String(36), nullable=False, index=True)
    subscription_id = Column(String(36), nullable=True, index=True)
    amount_cents = Column(BigInteger, nullable=False)
    currency = Column(String(8), nullable=False, default="USD")
    payment_provider = Column(String(32), nullable=False, default="stripe")
    payment_reference = Column(String(128), nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())

    __table_args__ = (
        CheckConstraint("amount_cents > 0", name="ck_golf_charity_donation_amount"),
    )


class GolfReferralCode(BaseGolf):
    __tablename__ = "golf_referral_codes"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(Integer, nullable=False, unique=True, index=True)
    code = Column(String(24), nullable=False, unique=True, index=True)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())


class GolfReferral(BaseGolf):
    __tablename__ = "golf_referrals"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    referrer_user_id = Column(Integer, nullable=False, index=True)
    referred_user_id = Column(Integer, nullable=False, unique=True, index=True)
    referral_code = Column(String(24), nullable=False, index=True)
    status = Column(String(16), nullable=False, default="captured", index=True)
    reward_amount_usd = Column(Numeric(8, 2), nullable=False, default=Decimal("20.00"))
    captured_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    qualified_at = Column(DateTime(timezone=True), nullable=True)
    rewarded_at = Column(DateTime(timezone=True), nullable=True)
    rewarded_subscription_id = Column(String(36), nullable=True, index=True)

    __table_args__ = (
        CheckConstraint(
            "status in ('captured','qualified','rewarded','rejected')",
            name="ck_golf_referral_status",
        ),
        CheckConstraint(
            "referrer_user_id <> referred_user_id",
            name="ck_golf_referral_no_self",
        ),
    )


class GolfScore(BaseGolf):
    __tablename__ = "golf_scores"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(Integer, nullable=False, index=True)
    course_name = Column(String(200), nullable=False)
    score = Column(Integer, nullable=False)
    played_on = Column(Date, nullable=False, default=date.today)
    is_verified = Column(Boolean, nullable=False, default=False)
    source = Column(String(24), nullable=False, default="manual")
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        CheckConstraint("score >= 1 and score <= 45", name="ck_golf_score_range"),
    )


class GolfUserCharitySetting(BaseGolf):
    __tablename__ = "golf_user_charity_settings"

    user_id = Column(Integer, primary_key=True)
    charity_id = Column(String(36), nullable=False, index=True)
    contribution_pct = Column(Numeric(5, 2), nullable=False, default=15)
    updated_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        CheckConstraint(
            "contribution_pct >= 10 and contribution_pct <= 100",
            name="ck_golf_contribution_pct",
        ),
    )


class GolfDraw(BaseGolf):
    __tablename__ = "golf_draws"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    month_key = Column(String(7), nullable=False, unique=True, index=True)
    status = Column(String(24), nullable=False, default="open", index=True)
    run_at = Column(DateTime(timezone=True), nullable=True)
    completed_at = Column(DateTime(timezone=True), nullable=True)
    draw_numbers = Column(JSONB, nullable=True)
    draw_seed = Column(String(128), nullable=True)
    pool_total_cents = Column(BigInteger, nullable=False, default=0)
    jackpot_carry_in_cents = Column(BigInteger, nullable=False, default=0)
    match5_pool_cents = Column(BigInteger, nullable=False, default=0)
    match4_pool_cents = Column(BigInteger, nullable=False, default=0)
    match3_pool_cents = Column(BigInteger, nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())

    __table_args__ = (
        CheckConstraint("status in ('open','closed','completed')", name="ck_golf_draw_status"),
    )


class GolfDrawSettings(BaseGolf):
    __tablename__ = "golf_draw_settings"

    id = Column(Integer, primary_key=True, default=1)
    weekly_prize_cents = Column(BigInteger, nullable=False, default=50000)
    monthly_first_prize_cents = Column(BigInteger, nullable=False, default=200000)
    monthly_second_prize_cents = Column(BigInteger, nullable=False, default=150000)
    monthly_third_prize_cents = Column(BigInteger, nullable=False, default=100000)
    monthly_min_events_required = Column(Integer, nullable=False, default=5)
    updated_by = Column(Integer, nullable=True, index=True)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    __table_args__ = (
        CheckConstraint("weekly_prize_cents >= 0", name="ck_draw_settings_weekly_nonnegative"),
        CheckConstraint(
            "monthly_first_prize_cents >= 0 and monthly_second_prize_cents >= 0 and monthly_third_prize_cents >= 0",
            name="ck_draw_settings_monthly_nonnegative",
        ),
        CheckConstraint(
            "monthly_first_prize_cents >= monthly_second_prize_cents and monthly_second_prize_cents >= monthly_third_prize_cents",
            name="ck_draw_settings_monthly_order",
        ),
        CheckConstraint(
            "monthly_min_events_required >= 1",
            name="ck_draw_settings_min_events",
        ),
    )


class GolfDrawEntry(BaseGolf):
    __tablename__ = "golf_draw_entries"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(Integer, nullable=False, index=True)
    draw_id = Column(String(36), nullable=False, index=True)
    score_id = Column(String(36), nullable=False, index=True)
    score_window = Column(JSONB, nullable=False)
    numbers = Column(JSONB, nullable=False)
    match_count = Column(Integer, nullable=True, index=True)
    is_winner = Column(Boolean, nullable=False, default=False, index=True)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())

    __table_args__ = (
        UniqueConstraint("draw_id", "score_id", name="uq_golf_draw_entry_draw_score"),
        Index("ix_golf_draw_entries_draw_user", "draw_id", "user_id"),
    )


class GolfPoolLedger(BaseGolf):
    __tablename__ = "golf_pool_ledger"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(Integer, nullable=False, index=True)
    subscription_id = Column(String(36), nullable=True, index=True)
    draw_id = Column(String(36), nullable=True, index=True)
    amount_cents = Column(BigInteger, nullable=False)
    source = Column(String(48), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())


class GolfPrizeRollover(BaseGolf):
    __tablename__ = "golf_prize_rollovers"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    from_draw_id = Column(String(36), nullable=False, index=True)
    amount_cents = Column(BigInteger, nullable=False)
    reason = Column(String(120), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())


class GolfWinnerClaim(BaseGolf):
    __tablename__ = "golf_winner_claims"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    draw_entry_id = Column(String(36), nullable=False, unique=True, index=True)
    user_id = Column(Integer, nullable=False, index=True)
    proof_url = Column(String(400), nullable=False)
    review_status = Column(String(16), nullable=False, default="pending", index=True)
    review_notes = Column(Text, nullable=True)
    reviewed_by = Column(Integer, nullable=True)
    reviewed_at = Column(DateTime(timezone=True), nullable=True)
    payout_state = Column(String(16), nullable=False, default="pending", index=True)
    payout_reference = Column(String(128), nullable=True)
    paid_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        CheckConstraint("review_status in ('pending','approved','rejected')", name="ck_golf_claim_review_status"),
        CheckConstraint("payout_state in ('pending','paid')", name="ck_golf_claim_payout_state"),
    )


class TournamentCourse(BaseGolf):
    __tablename__ = "tournament_courses"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    name = Column(String(200), nullable=False)
    location = Column(String(220), nullable=True)
    course_rating = Column(Numeric(4, 1), nullable=False)
    slope_rating = Column(Integer, nullable=False)
    holes_count = Column(Integer, nullable=False, default=18)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())

    __table_args__ = (
        CheckConstraint("holes_count in (9,18)", name="ck_tournament_courses_holes_count"),
        CheckConstraint("slope_rating >= 55 and slope_rating <= 155", name="ck_tournament_courses_slope_range"),
    )


class TournamentCourseHole(BaseGolf):
    __tablename__ = "tournament_course_holes"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    course_id = Column(String(36), ForeignKey("tournament_courses.id"), nullable=False, index=True)
    hole_number = Column(Integer, nullable=False)
    par = Column(Integer, nullable=False)
    yardage = Column(Integer, nullable=True)

    __table_args__ = (
        UniqueConstraint("course_id", "hole_number", name="uq_tournament_course_holes_course_hole"),
        CheckConstraint("hole_number >= 1 and hole_number <= 18", name="ck_tournament_course_holes_number"),
        CheckConstraint("par >= 3 and par <= 6", name="ck_tournament_course_holes_par"),
    )


class TournamentPlayerProfile(BaseGolf):
    __tablename__ = "tournament_player_profiles"

    user_id = Column(Integer, primary_key=True)
    club_affiliation = Column(String(160), nullable=True)
    handicap_index = Column(Numeric(5, 2), nullable=True)
    handicap_verified = Column(Boolean, nullable=False, default=False)
    handicap_source = Column(String(24), nullable=False, default="self_reported")
    trust_score = Column(Numeric(5, 2), nullable=False, default=Decimal("50.00"))
    updated_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        CheckConstraint(
            "handicap_source in ('official','uploaded_proof','self_reported')",
            name="ck_tournament_profiles_handicap_source",
        ),
        CheckConstraint("trust_score >= 0 and trust_score <= 100", name="ck_tournament_profiles_trust_score"),
    )


class TournamentRound(BaseGolf):
    __tablename__ = "tournament_rounds"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    player_user_id = Column(Integer, nullable=False, index=True)
    course_id = Column(String(36), ForeignKey("tournament_courses.id"), nullable=False, index=True)
    round_type = Column(String(12), nullable=False, default="18hole")
    played_at = Column(DateTime(timezone=True), nullable=False)
    status = Column(String(16), nullable=False, default="draft", index=True)
    marker_user_id = Column(Integer, nullable=True, index=True)
    submitted_at = Column(DateTime(timezone=True), nullable=True)
    verified_at = Column(DateTime(timezone=True), nullable=True)
    locked_at = Column(DateTime(timezone=True), nullable=True)
    gross_score = Column(Integer, nullable=True)
    total_putts = Column(Integer, nullable=True)
    gir_count = Column(Integer, nullable=True)
    fairways_hit_count = Column(Integer, nullable=True)
    penalties_total = Column(Integer, nullable=True)
    source = Column(String(24), nullable=False, default="manual")
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        CheckConstraint("round_type in ('9hole','18hole')", name="ck_tournament_round_type"),
        CheckConstraint(
            "status in ('draft','submitted','verified','locked','rejected')",
            name="ck_tournament_round_status",
        ),
        CheckConstraint("source in ('manual','live')", name="ck_tournament_round_source"),
    )


class TournamentRoundHole(BaseGolf):
    __tablename__ = "tournament_round_holes"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    round_id = Column(String(36), ForeignKey("tournament_rounds.id"), nullable=False, index=True)
    hole_number = Column(Integer, nullable=False)
    par = Column(Integer, nullable=False)
    strokes = Column(Integer, nullable=False)
    putts = Column(Integer, nullable=False)
    fairway_hit = Column(Boolean, nullable=True)
    gir = Column(Boolean, nullable=False, default=False)
    sand_save = Column(Boolean, nullable=False, default=False)
    penalties = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        UniqueConstraint("round_id", "hole_number", name="uq_tournament_round_holes_round_hole"),
        CheckConstraint("hole_number >= 1 and hole_number <= 18", name="ck_tournament_round_hole_number"),
        CheckConstraint("par >= 3 and par <= 6", name="ck_tournament_round_hole_par"),
        CheckConstraint("strokes >= 1 and strokes <= 15", name="ck_tournament_round_hole_strokes"),
        CheckConstraint("putts >= 0 and putts <= 8", name="ck_tournament_round_hole_putts"),
        CheckConstraint("penalties >= 0 and penalties <= 6", name="ck_tournament_round_hole_penalties"),
    )


class TournamentRoundVerification(BaseGolf):
    __tablename__ = "tournament_round_verifications"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    round_id = Column(String(36), ForeignKey("tournament_rounds.id"), nullable=False, unique=True, index=True)
    marker_user_id = Column(Integer, nullable=False, index=True)
    marker_confirmed = Column(Boolean, nullable=False, default=False)
    marker_confirmed_at = Column(DateTime(timezone=True), nullable=True)
    co_player_confirmations = Column(JSONB, nullable=True)
    verification_notes = Column(Text, nullable=True)
    rejection_reason = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now())


class TournamentRoundAuditEvent(BaseGolf):
    __tablename__ = "tournament_round_audit_events"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    round_id = Column(String(36), ForeignKey("tournament_rounds.id"), nullable=False, index=True)
    actor_user_id = Column(Integer, nullable=False, index=True)
    event_type = Column(String(32), nullable=False)
    payload = Column(JSONB, nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())


class TournamentPlayerMetricSnapshot(BaseGolf):
    __tablename__ = "tournament_player_metric_snapshots"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(Integer, nullable=False, index=True)
    as_of = Column(DateTime(timezone=True), nullable=False, index=True)
    rounds_used = Column(Integer, nullable=False)
    avg_score = Column(Numeric(6, 2), nullable=False)
    handicap_differential_avg = Column(Numeric(6, 2), nullable=False)
    gir_pct = Column(Numeric(6, 2), nullable=False)
    fairways_hit_pct = Column(Numeric(6, 2), nullable=False)
    putts_per_round = Column(Numeric(6, 2), nullable=False)
    std_dev_score = Column(Numeric(6, 2), nullable=False)
    recent_form_score = Column(Numeric(6, 2), nullable=False)
    strokes_gained_total = Column(Numeric(6, 2), nullable=True)
    confidence_score = Column(Numeric(5, 2), nullable=False)


class TournamentPlayerRating(BaseGolf):
    __tablename__ = "tournament_player_ratings"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(Integer, nullable=False, index=True)
    as_of = Column(DateTime(timezone=True), nullable=False, index=True)
    rating_formula_version = Column(String(24), nullable=False, default="v1.0")
    rating_score = Column(Numeric(5, 2), nullable=False)
    confidence_score = Column(Numeric(5, 2), nullable=False)

    __table_args__ = (
        CheckConstraint("rating_score >= 0 and rating_score <= 100", name="ck_tournament_rating_score"),
        CheckConstraint("confidence_score >= 0 and confidence_score <= 100", name="ck_tournament_rating_confidence"),
    )


class TournamentFraudFlag(BaseGolf):
    __tablename__ = "tournament_fraud_flags"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(Integer, nullable=False, index=True)
    round_id = Column(String(36), ForeignKey("tournament_rounds.id"), nullable=True, index=True)
    flag_type = Column(String(40), nullable=False, index=True)
    severity = Column(String(12), nullable=False, default="low")
    details = Column(JSONB, nullable=True)
    status = Column(String(16), nullable=False, default="open", index=True)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())

    __table_args__ = (
        CheckConstraint("severity in ('low','medium','high')", name="ck_tournament_fraud_severity"),
        CheckConstraint("status in ('open','reviewed','dismissed')", name="ck_tournament_fraud_status"),
    )


class TournamentTeamDrawRun(BaseGolf):
    __tablename__ = "tournament_team_draw_runs"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    event_key = Column(String(80), nullable=False, index=True)
    algorithm = Column(String(24), nullable=False, default="balanced_sum")
    constraints_json = Column(JSONB, nullable=True)
    created_by = Column(Integer, nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    balance_score = Column(Numeric(6, 2), nullable=False, default=0)

    __table_args__ = (
        CheckConstraint(
            "algorithm in ('balanced_sum','snake','tier','weighted_random')",
            name="ck_tournament_team_draw_algorithm",
        ),
    )


class TournamentTeamAssignment(BaseGolf):
    __tablename__ = "tournament_team_assignments"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    draw_run_id = Column(String(36), ForeignKey("tournament_team_draw_runs.id"), nullable=False, index=True)
    team_label = Column(String(24), nullable=False, index=True)
    user_id = Column(Integer, nullable=False, index=True)
    player_rating = Column(Numeric(5, 2), nullable=False)
    trust_score = Column(Numeric(5, 2), nullable=False)


class TournamentEvent(BaseGolf):
    __tablename__ = "tournament_events"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    title = Column(String(180), nullable=False)
    event_type = Column(String(24), nullable=False, index=True)
    description = Column(Text, nullable=True)
    min_donation_cents = Column(Integer, nullable=False)
    currency = Column(String(8), nullable=False, default="USD")
    unlock_mode = Column(String(24), nullable=False, default="single_use_ticket")
    start_at = Column(DateTime(timezone=True), nullable=False, index=True)
    end_at = Column(DateTime(timezone=True), nullable=False, index=True)
    status = Column(String(16), nullable=False, default="draft", index=True)
    max_participants = Column(Integer, nullable=True)
    created_by = Column(Integer, nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())

    __table_args__ = (
        CheckConstraint(
            "event_type in ('one_on_one','skill_challenge','group_challenge','charity_sprint')",
            name="ck_tournament_event_type",
        ),
        CheckConstraint(
            "unlock_mode in ('single_use_ticket','window_access')",
            name="ck_tournament_event_unlock_mode",
        ),
        CheckConstraint(
            "status in ('draft','active','closed','cancelled')",
            name="ck_tournament_event_status",
        ),
        CheckConstraint("min_donation_cents >= 1", name="ck_tournament_event_min_donation"),
    )


class TournamentEventDonation(BaseGolf):
    __tablename__ = "tournament_event_donations"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(Integer, nullable=False, index=True)
    event_id = Column(String(36), ForeignKey("tournament_events.id"), nullable=False, index=True)
    amount_cents = Column(Integer, nullable=False)
    currency = Column(String(8), nullable=False, default="USD")
    provider = Column(String(24), nullable=False, default="mpesa")
    provider_ref = Column(String(128), nullable=False, index=True)
    transaction_id = Column(Integer, nullable=True, index=True)
    status = Column(String(16), nullable=False, default="pending", index=True)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    completed_at = Column(DateTime(timezone=True), nullable=True)

    __table_args__ = (
        CheckConstraint("amount_cents >= 1", name="ck_tournament_event_donation_amount"),
        CheckConstraint(
            "status in ('pending','completed','failed','refunded')",
            name="ck_tournament_event_donation_status",
        ),
        UniqueConstraint("provider_ref", name="uq_tournament_event_donation_provider_ref"),
    )


class TournamentEventUnlock(BaseGolf):
    __tablename__ = "tournament_event_unlocks"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(Integer, nullable=False, index=True)
    event_id = Column(String(36), ForeignKey("tournament_events.id"), nullable=False, index=True)
    donation_id = Column(String(36), ForeignKey("tournament_event_donations.id"), nullable=False, unique=True, index=True)
    unlock_mode = Column(String(24), nullable=False)
    ticket_count = Column(Integer, nullable=False, default=1)
    tickets_used = Column(Integer, nullable=False, default=0)
    unlocked_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    expires_at = Column(DateTime(timezone=True), nullable=True, index=True)
    status = Column(String(16), nullable=False, default="active", index=True)

    __table_args__ = (
        CheckConstraint("ticket_count >= 1", name="ck_tournament_event_unlock_ticket_count"),
        CheckConstraint("tickets_used >= 0", name="ck_tournament_event_unlock_tickets_used"),
        CheckConstraint(
            "status in ('active','consumed','expired','revoked')",
            name="ck_tournament_event_unlock_status",
        ),
    )


class TournamentEventParticipant(BaseGolf):
    __tablename__ = "tournament_event_participants"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    event_id = Column(String(36), ForeignKey("tournament_events.id"), nullable=False, index=True)
    user_id = Column(Integer, nullable=False, index=True)
    unlock_id = Column(String(36), ForeignKey("tournament_event_unlocks.id"), nullable=False, index=True)
    joined_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    state = Column(String(16), nullable=False, default="joined")

    __table_args__ = (
        CheckConstraint(
            "state in ('joined','active','completed','withdrawn')",
            name="ck_tournament_event_participant_state",
        ),
        UniqueConstraint("event_id", "user_id", name="uq_tournament_event_participant_unique"),
    )


class TournamentChallengeSession(BaseGolf):
    __tablename__ = "tournament_challenge_sessions"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    event_id = Column(String(36), ForeignKey("tournament_events.id"), nullable=False, index=True)
    event_type = Column(String(24), nullable=False, index=True)
    creator_user_id = Column(Integer, nullable=False, index=True)
    scheduled_at = Column(DateTime(timezone=True), nullable=False, index=True)
    status = Column(String(20), nullable=False, default="pending_invites", index=True)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    started_at = Column(DateTime(timezone=True), nullable=True)
    auto_close_at = Column(DateTime(timezone=True), nullable=True, index=True)
    completed_at = Column(DateTime(timezone=True), nullable=True)

    __table_args__ = (
        CheckConstraint(
            "status in ('pending_invites','ready_to_start','in_progress','completed','auto_closed','cancelled')",
            name="ck_tournament_challenge_session_status",
        ),
        CheckConstraint(
            "event_type in ('one_on_one','skill_challenge','group_challenge','charity_sprint')",
            name="ck_tournament_challenge_session_type",
        ),
    )


class TournamentChallengeParticipant(BaseGolf):
    __tablename__ = "tournament_challenge_participants"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    session_id = Column(String(36), ForeignKey("tournament_challenge_sessions.id"), nullable=False, index=True)
    user_id = Column(Integer, nullable=False, index=True)
    role = Column(String(16), nullable=False, default="player")
    invite_state = Column(String(16), nullable=False, default="pending", index=True)
    joined_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())

    __table_args__ = (
        UniqueConstraint("session_id", "user_id", name="uq_tournament_challenge_participant_session_user"),
        CheckConstraint("role in ('player','marker')", name="ck_tournament_challenge_participant_role"),
        CheckConstraint(
            "invite_state in ('pending','accepted','declined')",
            name="ck_tournament_challenge_participant_invite_state",
        ),
    )


class TournamentFriendRequest(BaseGolf):
    __tablename__ = "tournament_friend_requests"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    sender_user_id = Column(Integer, nullable=False, index=True)
    receiver_user_id = Column(Integer, nullable=False, index=True)
    status = Column(String(16), nullable=False, default="pending", index=True)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    responded_at = Column(DateTime(timezone=True), nullable=True)

    __table_args__ = (
        CheckConstraint(
            "status in ('pending','accepted','declined','cancelled')",
            name="ck_tournament_friend_request_status",
        ),
        CheckConstraint(
            "sender_user_id <> receiver_user_id",
            name="ck_tournament_friend_request_no_self",
        ),
    )


class TournamentInboxMessage(BaseGolf):
    __tablename__ = "tournament_inbox_messages"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    recipient_user_id = Column(Integer, nullable=False, index=True)
    sender_user_id = Column(Integer, nullable=False, index=True)
    session_id = Column(String(36), ForeignKey("tournament_challenge_sessions.id"), nullable=True, index=True)
    related_score_id = Column(String(36), nullable=True, index=True)
    message_type = Column(String(32), nullable=False, index=True)
    title = Column(String(180), nullable=False)
    body = Column(Text, nullable=False)
    status = Column(String(16), nullable=False, default="unread", index=True)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    actioned_at = Column(DateTime(timezone=True), nullable=True)

    __table_args__ = (
        CheckConstraint(
            "message_type in ('invite','system','score_confirmation_request','score_confirmation_result')",
            name="ck_tournament_inbox_message_type",
        ),
        CheckConstraint(
            "status in ('unread','read','accepted','declined')",
            name="ck_tournament_inbox_message_status",
        ),
    )


class TournamentSessionScore(BaseGolf):
    __tablename__ = "tournament_session_scores"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    session_id = Column(String(36), ForeignKey("tournament_challenge_sessions.id"), nullable=False, index=True)
    player_user_id = Column(Integer, nullable=False, index=True)
    marker_user_id = Column(Integer, nullable=False, index=True)
    total_score = Column(Integer, nullable=False)
    holes_played = Column(Integer, nullable=True)
    total_putts = Column(Integer, nullable=True)
    gir_count = Column(Integer, nullable=True)
    fairways_hit_count = Column(Integer, nullable=True)
    penalties_total = Column(Integer, nullable=True)
    notes = Column(Text, nullable=True)
    status = Column(String(24), nullable=False, default="pending_confirmation", index=True)
    submitted_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    reviewed_at = Column(DateTime(timezone=True), nullable=True)
    rejection_reason = Column(Text, nullable=True)

    __table_args__ = (
        CheckConstraint(
            "status in ('pending_confirmation','confirmed','rejected')",
            name="ck_tournament_session_score_status",
        ),
        CheckConstraint("total_score >= 18 and total_score <= 200", name="ck_tournament_session_score_total"),
        CheckConstraint(
            "holes_played is null or holes_played in (9,18)",
            name="ck_tournament_session_score_holes_played",
        ),
        CheckConstraint(
            "total_putts is null or (total_putts >= 0 and total_putts <= 120)",
            name="ck_tournament_session_score_putts",
        ),
        CheckConstraint(
            "gir_count is null or (gir_count >= 0 and gir_count <= 18)",
            name="ck_tournament_session_score_gir",
        ),
        CheckConstraint(
            "fairways_hit_count is null or (fairways_hit_count >= 0 and fairways_hit_count <= 18)",
            name="ck_tournament_session_score_fairways",
        ),
        CheckConstraint(
            "penalties_total is null or (penalties_total >= 0 and penalties_total <= 30)",
            name="ck_tournament_session_score_penalties",
        ),
    )


class TournamentSessionScoreHole(BaseGolf):
    __tablename__ = "tournament_session_score_holes"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    score_id = Column(String(36), ForeignKey("tournament_session_scores.id"), nullable=False, index=True)
    hole_number = Column(Integer, nullable=False)
    score = Column(Integer, nullable=False)

    __table_args__ = (
        UniqueConstraint("score_id", "hole_number", name="uq_tournament_session_score_hole"),
        CheckConstraint("hole_number >= 1 and hole_number <= 18", name="ck_tournament_session_score_hole_number"),
        CheckConstraint("score >= 1 and score <= 15", name="ck_tournament_session_score_hole_score"),
    )


class TournamentScoreboardEntry(BaseGolf):
    __tablename__ = "tournament_scoreboard_entries"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    session_id = Column(String(36), ForeignKey("tournament_challenge_sessions.id"), nullable=False, index=True)
    score_id = Column(String(36), ForeignKey("tournament_session_scores.id"), nullable=False, unique=True, index=True)
    player_user_id = Column(Integer, nullable=False, index=True)
    total_score = Column(Integer, nullable=False)
    confirmed_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
