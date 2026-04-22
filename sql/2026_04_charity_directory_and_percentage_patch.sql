ALTER TABLE golf_charities
    ADD COLUMN IF NOT EXISTS cause VARCHAR(80),
    ADD COLUMN IF NOT EXISTS location VARCHAR(120),
    ADD COLUMN IF NOT EXISTS hero_image_url VARCHAR(500),
    ADD COLUMN IF NOT EXISTS gallery_image_urls JSONB,
    ADD COLUMN IF NOT EXISTS upcoming_events JSONB,
    ADD COLUMN IF NOT EXISTS spotlight_text TEXT,
    ADD COLUMN IF NOT EXISTS is_featured BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS ix_golf_charities_cause ON golf_charities(cause);
CREATE INDEX IF NOT EXISTS ix_golf_charities_is_featured ON golf_charities(is_featured);

UPDATE golf_user_charity_settings
SET contribution_pct = 10
WHERE contribution_pct IS NULL OR contribution_pct < 10;

ALTER TABLE golf_user_charity_settings
    DROP CONSTRAINT IF EXISTS ck_golf_contribution_pct;

ALTER TABLE golf_user_charity_settings
    ADD CONSTRAINT ck_golf_contribution_pct
    CHECK (contribution_pct >= 10 AND contribution_pct <= 100);

INSERT INTO golf_subscription_plans (id, name, interval, amount_cents, currency, discount_pct, is_active)
VALUES
    ('monthly', 'Monthly', 'monthly', 999, 'USD', 0, TRUE),
    ('yearly', 'Yearly', 'yearly', 4999, 'USD', 58.30, TRUE)
ON CONFLICT (id) DO UPDATE
SET amount_cents = EXCLUDED.amount_cents,
    discount_pct = EXCLUDED.discount_pct,
    is_active = TRUE;
