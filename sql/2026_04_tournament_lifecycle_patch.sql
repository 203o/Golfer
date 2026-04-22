-- Patch existing tournament schema for session lifecycle + unlock persistence.

ALTER TABLE tournament_challenge_sessions
    ADD COLUMN IF NOT EXISTS auto_close_at TIMESTAMPTZ;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'tournament_challenge_sessions_status_check'
    ) THEN
        ALTER TABLE tournament_challenge_sessions
            DROP CONSTRAINT tournament_challenge_sessions_status_check;
    END IF;
EXCEPTION
    WHEN undefined_table THEN
        NULL;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'ck_tournament_challenge_session_status'
    ) THEN
        ALTER TABLE tournament_challenge_sessions
            DROP CONSTRAINT ck_tournament_challenge_session_status;
    END IF;
EXCEPTION
    WHEN undefined_table THEN
        NULL;
END $$;

ALTER TABLE tournament_challenge_sessions
    ADD CONSTRAINT ck_tournament_challenge_session_status
    CHECK (status IN ('pending_invites','ready_to_start','in_progress','completed','auto_closed','cancelled'));

-- Preserve paid-access semantics for standard events.
UPDATE tournament_events
SET unlock_mode = 'window_access'
WHERE event_type IN ('one_on_one','skill_challenge','group_challenge','charity_sprint')
  AND unlock_mode <> 'window_access';

