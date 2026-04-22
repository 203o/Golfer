-- Golf Charity Draw domain schema (FastAPI-first)
-- Created: 2026-04-20

CREATE TABLE IF NOT EXISTS golf_charities (
    id UUID PRIMARY KEY,
    name VARCHAR(160) NOT NULL UNIQUE,
    slug VARCHAR(180) NOT NULL UNIQUE,
    description TEXT,
    cause VARCHAR(80),
    location VARCHAR(120),
    website_url VARCHAR(300),
    hero_image_url VARCHAR(500),
    gallery_image_urls JSONB,
    upcoming_events JSONB,
    spotlight_text TEXT,
    is_featured BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    total_raised_cents BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_golf_charities_cause ON golf_charities(cause);
CREATE INDEX IF NOT EXISTS ix_golf_charities_is_featured ON golf_charities(is_featured);

CREATE TABLE IF NOT EXISTS golf_subscription_plans (
    id VARCHAR(32) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    interval VARCHAR(16) NOT NULL CHECK (interval IN ('monthly', 'yearly')),
    amount_cents INTEGER NOT NULL,
    currency VARCHAR(8) NOT NULL DEFAULT 'USD',
    discount_pct NUMERIC(5,2) NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO golf_subscription_plans (id, name, interval, amount_cents, currency, discount_pct, is_active)
VALUES
    ('monthly', 'Monthly', 'monthly', 999, 'USD', 0, TRUE),
    ('yearly', 'Yearly', 'yearly', 4999, 'USD', 58.30, TRUE)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS golf_subscriptions (
    id UUID PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plan_id VARCHAR(32) NOT NULL REFERENCES golf_subscription_plans(id),
    status VARCHAR(24) NOT NULL CHECK (status IN ('active', 'inactive', 'cancelled', 'lapsed')),
    started_at TIMESTAMPTZ NOT NULL,
    current_period_start TIMESTAMPTZ NOT NULL,
    current_period_end TIMESTAMPTZ NOT NULL,
    renewal_date TIMESTAMPTZ NOT NULL,
    cancel_at_period_end BOOLEAN NOT NULL DEFAULT FALSE,
    cancelled_at TIMESTAMPTZ,
    lapsed_at TIMESTAMPTZ,
    payment_provider VARCHAR(32) NOT NULL DEFAULT 'stripe',
    payment_customer_id VARCHAR(128),
    payment_subscription_id VARCHAR(128),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS golf_subscription_payments (
    id UUID PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subscription_id UUID NOT NULL REFERENCES golf_subscriptions(id) ON DELETE CASCADE,
    plan_id VARCHAR(32) NOT NULL REFERENCES golf_subscription_plans(id),
    amount_cents BIGINT NOT NULL CHECK (amount_cents > 0),
    currency VARCHAR(8) NOT NULL DEFAULT 'USD',
    payment_provider VARCHAR(32) NOT NULL DEFAULT 'stripe',
    payment_reference VARCHAR(128),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_golf_subscription_payments_user ON golf_subscription_payments(user_id);
CREATE INDEX IF NOT EXISTS ix_golf_subscription_payments_subscription ON golf_subscription_payments(subscription_id);

CREATE TABLE IF NOT EXISTS golf_charity_donations (
    id UUID PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    charity_id UUID NOT NULL REFERENCES golf_charities(id) ON DELETE CASCADE,
    subscription_id UUID REFERENCES golf_subscriptions(id) ON DELETE SET NULL,
    amount_cents BIGINT NOT NULL CHECK (amount_cents > 0),
    currency VARCHAR(8) NOT NULL DEFAULT 'USD',
    payment_provider VARCHAR(32) NOT NULL DEFAULT 'stripe',
    payment_reference VARCHAR(128),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_golf_charity_donations_user ON golf_charity_donations(user_id);
CREATE INDEX IF NOT EXISTS ix_golf_charity_donations_charity ON golf_charity_donations(charity_id);

CREATE INDEX IF NOT EXISTS ix_golf_subscriptions_user_id ON golf_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS ix_golf_subscriptions_status ON golf_subscriptions(status);
CREATE INDEX IF NOT EXISTS ix_golf_subscriptions_current_period_end ON golf_subscriptions(current_period_end);

CREATE TABLE IF NOT EXISTS golf_scores (
    id UUID PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    course_name VARCHAR(200) NOT NULL,
    score INTEGER NOT NULL CHECK (score BETWEEN 18 AND 150),
    played_on DATE NOT NULL,
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    source VARCHAR(24) NOT NULL DEFAULT 'manual',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_golf_scores_user_id ON golf_scores(user_id);
CREATE INDEX IF NOT EXISTS ix_golf_scores_played_on ON golf_scores(played_on);

CREATE TABLE IF NOT EXISTS golf_user_charity_settings (
    user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    charity_id UUID NOT NULL REFERENCES golf_charities(id),
    contribution_pct NUMERIC(5,2) NOT NULL CHECK (contribution_pct >= 10 AND contribution_pct <= 100),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_golf_user_charity_settings_charity_id ON golf_user_charity_settings(charity_id);

CREATE TABLE IF NOT EXISTS golf_draws (
    id UUID PRIMARY KEY,
    month_key VARCHAR(7) NOT NULL UNIQUE,
    status VARCHAR(24) NOT NULL CHECK (status IN ('open', 'closed', 'completed')),
    run_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    draw_numbers JSONB,
    draw_seed VARCHAR(128),
    pool_total_cents BIGINT NOT NULL DEFAULT 0,
    jackpot_carry_in_cents BIGINT NOT NULL DEFAULT 0,
    match5_pool_cents BIGINT NOT NULL DEFAULT 0,
    match4_pool_cents BIGINT NOT NULL DEFAULT 0,
    match3_pool_cents BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_golf_draws_status ON golf_draws(status);

CREATE TABLE IF NOT EXISTS golf_draw_entries (
    id UUID PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    draw_id UUID NOT NULL REFERENCES golf_draws(id) ON DELETE CASCADE,
    score_id UUID NOT NULL REFERENCES golf_scores(id) ON DELETE CASCADE,
    score_window JSONB NOT NULL,
    numbers JSONB NOT NULL,
    match_count INTEGER,
    is_winner BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_golf_draw_entry_draw_score UNIQUE (draw_id, score_id)
);

CREATE INDEX IF NOT EXISTS ix_golf_draw_entries_draw_id ON golf_draw_entries(draw_id);
CREATE INDEX IF NOT EXISTS ix_golf_draw_entries_user_id ON golf_draw_entries(user_id);
CREATE INDEX IF NOT EXISTS ix_golf_draw_entries_match_count ON golf_draw_entries(match_count);
CREATE INDEX IF NOT EXISTS ix_golf_draw_entries_draw_user ON golf_draw_entries(draw_id, user_id);

CREATE TABLE IF NOT EXISTS golf_pool_ledger (
    id UUID PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subscription_id UUID REFERENCES golf_subscriptions(id) ON DELETE SET NULL,
    draw_id UUID REFERENCES golf_draws(id) ON DELETE SET NULL,
    amount_cents BIGINT NOT NULL,
    source VARCHAR(48) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_golf_pool_ledger_draw_id ON golf_pool_ledger(draw_id);
CREATE INDEX IF NOT EXISTS ix_golf_pool_ledger_user_id ON golf_pool_ledger(user_id);

CREATE TABLE IF NOT EXISTS golf_prize_rollovers (
    id UUID PRIMARY KEY,
    from_draw_id UUID NOT NULL REFERENCES golf_draws(id) ON DELETE CASCADE,
    amount_cents BIGINT NOT NULL,
    reason VARCHAR(120) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_golf_prize_rollovers_from_draw_id ON golf_prize_rollovers(from_draw_id);

CREATE TABLE IF NOT EXISTS golf_winner_claims (
    id UUID PRIMARY KEY,
    draw_entry_id UUID NOT NULL UNIQUE REFERENCES golf_draw_entries(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    proof_url VARCHAR(400) NOT NULL,
    review_status VARCHAR(16) NOT NULL CHECK (review_status IN ('pending', 'approved', 'rejected')),
    review_notes TEXT,
    reviewed_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    payout_state VARCHAR(16) NOT NULL CHECK (payout_state IN ('pending', 'paid')),
    payout_reference VARCHAR(128),
    paid_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_golf_winner_claims_review_status ON golf_winner_claims(review_status);
CREATE INDEX IF NOT EXISTS ix_golf_winner_claims_payout_state ON golf_winner_claims(payout_state);
CREATE INDEX IF NOT EXISTS ix_golf_winner_claims_user_id ON golf_winner_claims(user_id);
