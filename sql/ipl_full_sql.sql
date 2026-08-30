-- IPL ball-by-ball analytics
-- schema + cleaning views + all the analysis queries I actually ran
-- (Postgres, built/tested in pgAdmin)

-- ============================================================
-- 1. SCHEMA
-- ============================================================

CREATE TABLE matches (
    match_id            VARCHAR(20) PRIMARY KEY,
    match_date           DATE,
    season               VARCHAR(10),
    team1                VARCHAR(50),
    team2                VARCHAR(50),
    venue                VARCHAR(150),
    city                 VARCHAR(100),
    toss_winner          VARCHAR(50),
    toss_decision        VARCHAR(10),
    winner               VARCHAR(50),
    win_by_runs          INT,
    win_by_wickets       INT,
    player_of_match      VARCHAR(100)
);

CREATE TABLE deliveries (
    delivery_row_id      SERIAL PRIMARY KEY,
    match_id             VARCHAR(20) REFERENCES matches(match_id),
    innings_number        INT,
    batting_team          VARCHAR(50),
    over_number           INT,
    legal_ball_number     INT,          -- see parse_ipl_matches.py for why this exists (wide/no-ball label bug)
    is_legal_delivery     BOOLEAN,
    actual_delivery_label VARCHAR(10),
    batter                VARCHAR(100),
    bowler                VARCHAR(100),
    non_striker           VARCHAR(100),
    runs_batter           INT,
    runs_extras           INT,
    runs_total            INT,
    extras_type           VARCHAR(20),
    is_wicket             BOOLEAN,
    player_out            VARCHAR(100),
    wicket_kind           VARCHAR(30)
);

-- ============================================================
-- 2. CLEANING VIEWS
-- had to build these after noticing venue/team names weren't
-- consistent across seasons - see README for the actual bug writeup
-- ============================================================

-- venue names: same ground shows up under a few different strings
-- ("Wankhede Stadium" vs "Wankhede Stadium, Mumbai" etc) plus one
-- genuine rename (Punjab Cricket Association -> ...IS Bindra Stadium)
-- that the simple comma-split didn't catch, hence the ILIKE check
CREATE OR REPLACE VIEW matches_clean AS
SELECT
    match_id, match_date, season,
    CASE
        WHEN team1 IN ('Delhi Daredevils', 'Delhi Capitals') THEN 'Delhi Capitals'
        WHEN team1 IN ('Kings XI Punjab', 'Punjab Kings') THEN 'Punjab Kings'
        WHEN team1 IN ('Royal Challengers Bangalore', 'Royal Challengers Bengaluru') THEN 'Royal Challengers Bengaluru'
        WHEN team1 IN ('Rising Pune Supergiant', 'Rising Pune Supergiants') THEN 'Rising Pune Supergiant'
        ELSE team1
    END AS team1_clean,
    CASE
        WHEN team2 IN ('Delhi Daredevils', 'Delhi Capitals') THEN 'Delhi Capitals'
        WHEN team2 IN ('Kings XI Punjab', 'Punjab Kings') THEN 'Punjab Kings'
        WHEN team2 IN ('Royal Challengers Bangalore', 'Royal Challengers Bengaluru') THEN 'Royal Challengers Bengaluru'
        WHEN team2 IN ('Rising Pune Supergiant', 'Rising Pune Supergiants') THEN 'Rising Pune Supergiant'
        ELSE team2
    END AS team2_clean,
    venue,
    CASE
        WHEN venue ILIKE '%Punjab Cricket Association%' THEN 'Punjab Cricket Association Stadium'
        ELSE SPLIT_PART(venue, ',', 1)
    END AS canonical_venue,
    city, toss_winner, toss_decision, winner, win_by_runs, win_by_wickets, player_of_match
FROM matches;

-- note on team names: I deliberately did NOT merge Gujarat Lions with
-- Gujarat Titans, or Deccan Chargers with Sunrisers Hyderabad, even
-- though they look similar - checked the actual franchise history and
-- those are different ownership groups, not renames. Merging them
-- would've been wrong.

-- economy rate fix: byes/leg-byes shouldn't count against the bowler
-- (that's a fielding/keeping thing, not a bowling thing) - my first
-- version of this query used runs_total which included them, and it
-- was overstating some bowlers' economy. This version only charges
-- wides/no-balls to the bowler, which is how it's actually scored.
CREATE OR REPLACE VIEW bowler_death_stats AS
SELECT
    d.bowler,
    COUNT(*) FILTER (WHERE d.is_legal_delivery) AS legal_balls_bowled,
    SUM(
        d.runs_batter +
        CASE WHEN d.extras_type IN ('wides', 'noballs') THEN d.runs_extras ELSE 0 END
    ) AS bowler_runs_conceded,
    ROUND(
        SUM(d.runs_batter + CASE WHEN d.extras_type IN ('wides', 'noballs') THEN d.runs_extras ELSE 0 END)::NUMERIC
        / NULLIF(COUNT(*) FILTER (WHERE d.is_legal_delivery), 0) * 6,
    2) AS true_economy_rate,
    COUNT(*) FILTER (WHERE d.is_wicket) AS wickets
FROM deliveries d
WHERE d.over_number >= 15   -- death overs = 16-20, zero-indexed so >= 15
GROUP BY d.bowler;

-- ============================================================
-- 3. phase-wise run rate + wicket rate
-- basic question: do death overs actually score more, and if so
-- what's the wicket cost of that
-- ============================================================

SELECT
    CASE
        WHEN over_number < 6 THEN 'Powerplay (1-6)'
        WHEN over_number < 15 THEN 'Middle (7-15)'
        ELSE 'Death (16-20)'
    END AS phase,
    SUM(runs_total) AS total_runs,
    COUNT(*) FILTER (WHERE is_legal_delivery) AS legal_balls,
    ROUND(SUM(runs_total)::NUMERIC / NULLIF(COUNT(*) FILTER (WHERE is_legal_delivery), 0) * 6, 2) AS run_rate,
    COUNT(*) FILTER (WHERE is_wicket) AS wickets
FROM deliveries
GROUP BY phase
ORDER BY MIN(over_number);

-- ============================================================
-- 4. toss decision -> does winning the toss actually help
-- ============================================================

SELECT
    toss_decision,
    COUNT(*) AS total_matches,
    COUNT(*) FILTER (WHERE toss_winner = winner) AS toss_winner_won,
    ROUND(100.0 * COUNT(*) FILTER (WHERE toss_winner = winner) / COUNT(*), 2) AS toss_winner_win_pct
FROM matches
WHERE winner IS NOT NULL
GROUP BY toss_decision
ORDER BY toss_winner_win_pct DESC;

-- ============================================================
-- 5. chase vs defend, overall
-- ============================================================

SELECT
    CASE
        WHEN win_by_wickets IS NOT NULL THEN 'Chased successfully'
        WHEN win_by_runs IS NOT NULL THEN 'Defended successfully'
    END AS result_type,
    COUNT(*) AS matches,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_decisive_matches
FROM matches
WHERE winner IS NOT NULL
GROUP BY result_type;

-- ============================================================
-- 6. chase-win% by venue
-- this is the one where the raw numbers looked like a strong
-- venue effect (a ~26 point spread) but running confidence
-- intervals on this afterward showed most of that spread isn't
-- actually statistically significant given the sample sizes -
-- only Sawai Mansingh Stadium held up. see README for the full
-- writeup, didn't want to just report the flashy number without
-- checking if it was real
-- ============================================================

SELECT
    canonical_venue,
    COUNT(*) AS decisive_matches,
    COUNT(*) FILTER (WHERE win_by_wickets IS NOT NULL) AS chase_wins,
    ROUND(100.0 * COUNT(*) FILTER (WHERE win_by_wickets IS NOT NULL) / COUNT(*), 2) AS chase_win_pct
FROM matches_clean
WHERE winner IS NOT NULL
GROUP BY canonical_venue
HAVING COUNT(*) >= 15    -- cutting anything with too few matches to mean much
ORDER BY chase_win_pct DESC;

-- ============================================================
-- 7. death-over bowler value vs league average
-- raw economy rate alone is misleading (e.g. Bumrah's 8.2 looks
-- mediocre until you realize the death-over average is ~10) so
-- this baselines everyone against the league average instead
-- ============================================================

WITH death_baseline AS (
    SELECT AVG(true_economy_rate) AS league_avg FROM bowler_death_stats
)
SELECT
    b.bowler,
    b.legal_balls_bowled,
    b.true_economy_rate,
    ROUND(d.league_avg - b.true_economy_rate, 2) AS runs_saved_per_over_vs_league,
    b.wickets
FROM bowler_death_stats b, death_baseline d
WHERE b.legal_balls_bowled >= 120   -- roughly 20 overs of death bowling min, filters out small-sample flukes
ORDER BY runs_saved_per_over_vs_league DESC
LIMIT 15;
