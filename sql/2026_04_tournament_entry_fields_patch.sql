-- Patch existing databases to align tournament entry fields:
-- 1) Remove tee_box from tournament_rounds
-- 2) Add structured session entry fields (excluding weather/tee_box)

ALTER TABLE tournament_rounds
    DROP COLUMN IF EXISTS tee_box;

ALTER TABLE tournament_session_scores
    ADD COLUMN IF NOT EXISTS holes_played INTEGER,
    ADD COLUMN IF NOT EXISTS total_putts INTEGER,
    ADD COLUMN IF NOT EXISTS gir_count INTEGER,
    ADD COLUMN IF NOT EXISTS fairways_hit_count INTEGER,
    ADD COLUMN IF NOT EXISTS penalties_total INTEGER;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'ck_tournament_session_score_total'
    ) THEN
        ALTER TABLE tournament_session_scores
            DROP CONSTRAINT ck_tournament_session_score_total;
    END IF;

    ALTER TABLE tournament_session_scores
        ADD CONSTRAINT ck_tournament_session_score_total
        CHECK (total_score >= 1 AND total_score <= 200);
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'ck_tournament_session_score_holes_played'
    ) THEN
        ALTER TABLE tournament_session_scores
            ADD CONSTRAINT ck_tournament_session_score_holes_played
            CHECK (holes_played IS NULL OR holes_played IN (9,18));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'ck_tournament_session_score_putts'
    ) THEN
        ALTER TABLE tournament_session_scores
            ADD CONSTRAINT ck_tournament_session_score_putts
            CHECK (total_putts IS NULL OR (total_putts >= 0 AND total_putts <= 120));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'ck_tournament_session_score_gir'
    ) THEN
        ALTER TABLE tournament_session_scores
            ADD CONSTRAINT ck_tournament_session_score_gir
            CHECK (gir_count IS NULL OR (gir_count >= 0 AND gir_count <= 18));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'ck_tournament_session_score_fairways'
    ) THEN
        ALTER TABLE tournament_session_scores
            ADD CONSTRAINT ck_tournament_session_score_fairways
            CHECK (fairways_hit_count IS NULL OR (fairways_hit_count >= 0 AND fairways_hit_count <= 18));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'ck_tournament_session_score_penalties'
    ) THEN
        ALTER TABLE tournament_session_scores
            ADD CONSTRAINT ck_tournament_session_score_penalties
            CHECK (penalties_total IS NULL OR (penalties_total >= 0 AND penalties_total <= 30));
    END IF;
END $$;
