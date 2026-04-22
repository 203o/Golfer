-- Tournament V1 schema for FastAPI + Postgres

CREATE TABLE IF NOT EXISTS tournament_courses (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    location VARCHAR(220),
    course_rating NUMERIC(4,1) NOT NULL,
    slope_rating INTEGER NOT NULL CHECK (slope_rating >= 55 AND slope_rating <= 155),
    holes_count INTEGER NOT NULL CHECK (holes_count IN (9,18)),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tournament_course_holes (
    id VARCHAR(36) PRIMARY KEY,
    course_id VARCHAR(36) NOT NULL REFERENCES tournament_courses(id) ON DELETE CASCADE,
    hole_number INTEGER NOT NULL CHECK (hole_number >= 1 AND hole_number <= 18),
    par INTEGER NOT NULL CHECK (par >= 3 AND par <= 6),
    yardage INTEGER,
    UNIQUE (course_id, hole_number)
);

CREATE TABLE IF NOT EXISTS tournament_player_profiles (
    user_id INTEGER PRIMARY KEY,
    club_affiliation VARCHAR(160),
    handicap_index NUMERIC(5,2),
    handicap_verified BOOLEAN NOT NULL DEFAULT FALSE,
    handicap_source VARCHAR(24) NOT NULL DEFAULT 'self_reported'
        CHECK (handicap_source IN ('official','uploaded_proof','self_reported')),
    trust_score NUMERIC(5,2) NOT NULL DEFAULT 50.00 CHECK (trust_score >= 0 AND trust_score <= 100),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tournament_rounds (
    id VARCHAR(36) PRIMARY KEY,
    player_user_id INTEGER NOT NULL,
    course_id VARCHAR(36) NOT NULL REFERENCES tournament_courses(id),
    round_type VARCHAR(12) NOT NULL DEFAULT '18hole' CHECK (round_type IN ('9hole','18hole')),
    played_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','submitted','verified','locked','rejected')),
    marker_user_id INTEGER,
    submitted_at TIMESTAMPTZ,
    verified_at TIMESTAMPTZ,
    locked_at TIMESTAMPTZ,
    gross_score INTEGER,
    total_putts INTEGER,
    gir_count INTEGER,
    fairways_hit_count INTEGER,
    penalties_total INTEGER,
    source VARCHAR(24) NOT NULL DEFAULT 'manual' CHECK (source IN ('manual','live')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_tournament_rounds_player ON tournament_rounds(player_user_id);
CREATE INDEX IF NOT EXISTS ix_tournament_rounds_status ON tournament_rounds(status);
CREATE INDEX IF NOT EXISTS ix_tournament_rounds_marker ON tournament_rounds(marker_user_id);

CREATE TABLE IF NOT EXISTS tournament_round_holes (
    id VARCHAR(36) PRIMARY KEY,
    round_id VARCHAR(36) NOT NULL REFERENCES tournament_rounds(id) ON DELETE CASCADE,
    hole_number INTEGER NOT NULL CHECK (hole_number >= 1 AND hole_number <= 18),
    par INTEGER NOT NULL CHECK (par >= 3 AND par <= 6),
    strokes INTEGER NOT NULL CHECK (strokes >= 1 AND strokes <= 15),
    putts INTEGER NOT NULL CHECK (putts >= 0 AND putts <= 8),
    fairway_hit BOOLEAN,
    gir BOOLEAN NOT NULL DEFAULT FALSE,
    sand_save BOOLEAN NOT NULL DEFAULT FALSE,
    penalties INTEGER NOT NULL DEFAULT 0 CHECK (penalties >= 0 AND penalties <= 6),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (round_id, hole_number)
);

CREATE INDEX IF NOT EXISTS ix_tournament_round_holes_round ON tournament_round_holes(round_id);

CREATE TABLE IF NOT EXISTS tournament_round_verifications (
    id VARCHAR(36) PRIMARY KEY,
    round_id VARCHAR(36) NOT NULL UNIQUE REFERENCES tournament_rounds(id) ON DELETE CASCADE,
    marker_user_id INTEGER NOT NULL,
    marker_confirmed BOOLEAN NOT NULL DEFAULT FALSE,
    marker_confirmed_at TIMESTAMPTZ,
    co_player_confirmations JSONB,
    verification_notes TEXT,
    rejection_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tournament_round_audit_events (
    id VARCHAR(36) PRIMARY KEY,
    round_id VARCHAR(36) NOT NULL REFERENCES tournament_rounds(id) ON DELETE CASCADE,
    actor_user_id INTEGER NOT NULL,
    event_type VARCHAR(32) NOT NULL,
    payload JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_tournament_round_audit_round ON tournament_round_audit_events(round_id);

CREATE TABLE IF NOT EXISTS tournament_player_metric_snapshots (
    id VARCHAR(36) PRIMARY KEY,
    user_id INTEGER NOT NULL,
    as_of TIMESTAMPTZ NOT NULL,
    rounds_used INTEGER NOT NULL,
    avg_score NUMERIC(6,2) NOT NULL,
    handicap_differential_avg NUMERIC(6,2) NOT NULL,
    gir_pct NUMERIC(6,2) NOT NULL,
    fairways_hit_pct NUMERIC(6,2) NOT NULL,
    putts_per_round NUMERIC(6,2) NOT NULL,
    std_dev_score NUMERIC(6,2) NOT NULL,
    recent_form_score NUMERIC(6,2) NOT NULL,
    strokes_gained_total NUMERIC(6,2),
    confidence_score NUMERIC(5,2) NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_tournament_metric_snapshots_user_asof
    ON tournament_player_metric_snapshots(user_id, as_of DESC);

CREATE TABLE IF NOT EXISTS tournament_player_ratings (
    id VARCHAR(36) PRIMARY KEY,
    user_id INTEGER NOT NULL,
    as_of TIMESTAMPTZ NOT NULL,
    rating_formula_version VARCHAR(24) NOT NULL DEFAULT 'v1.0',
    rating_score NUMERIC(5,2) NOT NULL CHECK (rating_score >= 0 AND rating_score <= 100),
    confidence_score NUMERIC(5,2) NOT NULL CHECK (confidence_score >= 0 AND confidence_score <= 100)
);

CREATE INDEX IF NOT EXISTS ix_tournament_player_ratings_user_asof
    ON tournament_player_ratings(user_id, as_of DESC);

CREATE TABLE IF NOT EXISTS tournament_fraud_flags (
    id VARCHAR(36) PRIMARY KEY,
    user_id INTEGER NOT NULL,
    round_id VARCHAR(36) REFERENCES tournament_rounds(id) ON DELETE SET NULL,
    flag_type VARCHAR(40) NOT NULL,
    severity VARCHAR(12) NOT NULL DEFAULT 'low' CHECK (severity IN ('low','medium','high')),
    details JSONB,
    status VARCHAR(16) NOT NULL DEFAULT 'open' CHECK (status IN ('open','reviewed','dismissed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_tournament_fraud_flags_user_status
    ON tournament_fraud_flags(user_id, status);

CREATE TABLE IF NOT EXISTS tournament_team_draw_runs (
    id VARCHAR(36) PRIMARY KEY,
    event_key VARCHAR(80) NOT NULL,
    algorithm VARCHAR(24) NOT NULL CHECK (algorithm IN ('balanced_sum','snake','tier','weighted_random')),
    constraints_json JSONB,
    created_by INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    balance_score NUMERIC(6,2) NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS ix_tournament_team_draw_runs_event ON tournament_team_draw_runs(event_key);

CREATE TABLE IF NOT EXISTS tournament_team_assignments (
    id VARCHAR(36) PRIMARY KEY,
    draw_run_id VARCHAR(36) NOT NULL REFERENCES tournament_team_draw_runs(id) ON DELETE CASCADE,
    team_label VARCHAR(24) NOT NULL,
    user_id INTEGER NOT NULL,
    player_rating NUMERIC(5,2) NOT NULL,
    trust_score NUMERIC(5,2) NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_tournament_team_assignments_run
    ON tournament_team_assignments(draw_run_id, team_label);

CREATE TABLE IF NOT EXISTS tournament_events (
    id VARCHAR(36) PRIMARY KEY,
    title VARCHAR(180) NOT NULL,
    event_type VARCHAR(24) NOT NULL CHECK (event_type IN ('one_on_one','skill_challenge','group_challenge','charity_sprint')),
    description TEXT,
    min_donation_cents INTEGER NOT NULL CHECK (min_donation_cents >= 1),
    currency VARCHAR(8) NOT NULL DEFAULT 'USD',
    unlock_mode VARCHAR(24) NOT NULL CHECK (unlock_mode IN ('single_use_ticket','window_access')),
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','closed','cancelled')),
    max_participants INTEGER,
    created_by INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_tournament_events_status ON tournament_events(status);
CREATE INDEX IF NOT EXISTS ix_tournament_events_type ON tournament_events(event_type);

CREATE TABLE IF NOT EXISTS tournament_event_donations (
    id VARCHAR(36) PRIMARY KEY,
    user_id INTEGER NOT NULL,
    event_id VARCHAR(36) NOT NULL REFERENCES tournament_events(id) ON DELETE CASCADE,
    amount_cents INTEGER NOT NULL CHECK (amount_cents >= 1),
    currency VARCHAR(8) NOT NULL DEFAULT 'USD',
    provider VARCHAR(24) NOT NULL DEFAULT 'mpesa',
    provider_ref VARCHAR(128) NOT NULL,
    transaction_id INTEGER,
    status VARCHAR(16) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','completed','failed','refunded')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_tournament_event_donations_provider_ref ON tournament_event_donations(provider_ref);
CREATE INDEX IF NOT EXISTS ix_tournament_event_donations_event_user ON tournament_event_donations(event_id, user_id);

CREATE TABLE IF NOT EXISTS tournament_event_unlocks (
    id VARCHAR(36) PRIMARY KEY,
    user_id INTEGER NOT NULL,
    event_id VARCHAR(36) NOT NULL REFERENCES tournament_events(id) ON DELETE CASCADE,
    donation_id VARCHAR(36) NOT NULL UNIQUE REFERENCES tournament_event_donations(id) ON DELETE CASCADE,
    unlock_mode VARCHAR(24) NOT NULL,
    ticket_count INTEGER NOT NULL DEFAULT 1 CHECK (ticket_count >= 1),
    tickets_used INTEGER NOT NULL DEFAULT 0 CHECK (tickets_used >= 0),
    unlocked_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ,
    status VARCHAR(16) NOT NULL DEFAULT 'active' CHECK (status IN ('active','consumed','expired','revoked'))
);

CREATE INDEX IF NOT EXISTS ix_tournament_event_unlocks_event_user ON tournament_event_unlocks(event_id, user_id);

CREATE TABLE IF NOT EXISTS tournament_event_participants (
    id VARCHAR(36) PRIMARY KEY,
    event_id VARCHAR(36) NOT NULL REFERENCES tournament_events(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL,
    unlock_id VARCHAR(36) NOT NULL REFERENCES tournament_event_unlocks(id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    state VARCHAR(16) NOT NULL DEFAULT 'joined' CHECK (state IN ('joined','active','completed','withdrawn')),
    UNIQUE (event_id, user_id)
);

CREATE INDEX IF NOT EXISTS ix_tournament_event_participants_event ON tournament_event_participants(event_id);

CREATE TABLE IF NOT EXISTS tournament_challenge_sessions (
    id VARCHAR(36) PRIMARY KEY,
    event_id VARCHAR(36) NOT NULL REFERENCES tournament_events(id) ON DELETE CASCADE,
    event_type VARCHAR(24) NOT NULL CHECK (event_type IN ('one_on_one','skill_challenge','group_challenge','charity_sprint')),
    creator_user_id INTEGER NOT NULL,
    scheduled_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending_invites' CHECK (status IN ('pending_invites','ready_to_start','in_progress','completed','auto_closed','cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at TIMESTAMPTZ,
    auto_close_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS ix_tournament_challenge_sessions_event ON tournament_challenge_sessions(event_id);
CREATE INDEX IF NOT EXISTS ix_tournament_challenge_sessions_creator ON tournament_challenge_sessions(creator_user_id);

CREATE TABLE IF NOT EXISTS tournament_challenge_participants (
    id VARCHAR(36) PRIMARY KEY,
    session_id VARCHAR(36) NOT NULL REFERENCES tournament_challenge_sessions(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL,
    role VARCHAR(16) NOT NULL DEFAULT 'player' CHECK (role IN ('player','marker')),
    invite_state VARCHAR(16) NOT NULL DEFAULT 'pending' CHECK (invite_state IN ('pending','accepted','declined')),
    joined_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (session_id, user_id)
);

CREATE INDEX IF NOT EXISTS ix_tournament_challenge_participants_session ON tournament_challenge_participants(session_id);
CREATE INDEX IF NOT EXISTS ix_tournament_challenge_participants_user ON tournament_challenge_participants(user_id);

CREATE TABLE IF NOT EXISTS tournament_friend_requests (
    id VARCHAR(36) PRIMARY KEY,
    sender_user_id INTEGER NOT NULL,
    receiver_user_id INTEGER NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','accepted','declined','cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    responded_at TIMESTAMPTZ,
    CHECK (sender_user_id <> receiver_user_id)
);

CREATE INDEX IF NOT EXISTS ix_tournament_friend_requests_sender_status
    ON tournament_friend_requests(sender_user_id, status);
CREATE INDEX IF NOT EXISTS ix_tournament_friend_requests_receiver_status
    ON tournament_friend_requests(receiver_user_id, status);

CREATE TABLE IF NOT EXISTS tournament_inbox_messages (
    id VARCHAR(36) PRIMARY KEY,
    recipient_user_id INTEGER NOT NULL,
    sender_user_id INTEGER NOT NULL,
    session_id VARCHAR(36) REFERENCES tournament_challenge_sessions(id) ON DELETE CASCADE,
    related_score_id VARCHAR(36),
    message_type VARCHAR(32) NOT NULL CHECK (message_type IN ('invite','system','score_confirmation_request','score_confirmation_result')),
    title VARCHAR(180) NOT NULL,
    body TEXT NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'unread' CHECK (status IN ('unread','read','accepted','declined')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    actioned_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS ix_tournament_inbox_recipient ON tournament_inbox_messages(recipient_user_id, status);

CREATE TABLE IF NOT EXISTS tournament_session_scores (
    id VARCHAR(36) PRIMARY KEY,
    session_id VARCHAR(36) NOT NULL REFERENCES tournament_challenge_sessions(id) ON DELETE CASCADE,
    player_user_id INTEGER NOT NULL,
    marker_user_id INTEGER NOT NULL,
    total_score INTEGER NOT NULL CHECK (total_score >= 18 AND total_score <= 200),
    holes_played INTEGER CHECK (holes_played IN (9,18)),
    total_putts INTEGER CHECK (total_putts >= 0 AND total_putts <= 120),
    gir_count INTEGER CHECK (gir_count >= 0 AND gir_count <= 18),
    fairways_hit_count INTEGER CHECK (fairways_hit_count >= 0 AND fairways_hit_count <= 18),
    penalties_total INTEGER CHECK (penalties_total >= 0 AND penalties_total <= 30),
    notes TEXT,
    status VARCHAR(24) NOT NULL DEFAULT 'pending_confirmation' CHECK (status IN ('pending_confirmation','confirmed','rejected')),
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_at TIMESTAMPTZ,
    rejection_reason TEXT
);

CREATE INDEX IF NOT EXISTS ix_tournament_session_scores_session ON tournament_session_scores(session_id);
CREATE INDEX IF NOT EXISTS ix_tournament_session_scores_marker_status ON tournament_session_scores(marker_user_id, status);

CREATE TABLE IF NOT EXISTS tournament_session_score_holes (
    id VARCHAR(36) PRIMARY KEY,
    score_id VARCHAR(36) NOT NULL REFERENCES tournament_session_scores(id) ON DELETE CASCADE,
    hole_number INTEGER NOT NULL CHECK (hole_number >= 1 AND hole_number <= 18),
    score INTEGER NOT NULL CHECK (score >= 1 AND score <= 15),
    UNIQUE (score_id, hole_number)
);

CREATE TABLE IF NOT EXISTS tournament_scoreboard_entries (
    id VARCHAR(36) PRIMARY KEY,
    session_id VARCHAR(36) NOT NULL REFERENCES tournament_challenge_sessions(id) ON DELETE CASCADE,
    score_id VARCHAR(36) NOT NULL UNIQUE REFERENCES tournament_session_scores(id) ON DELETE CASCADE,
    player_user_id INTEGER NOT NULL,
    total_score INTEGER NOT NULL,
    confirmed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_tournament_scoreboard_session ON tournament_scoreboard_entries(session_id);
