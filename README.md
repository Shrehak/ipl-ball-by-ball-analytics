# IPL Ball-by-Ball Analytics

An end-to-end data analytics project built from raw match data — not a pre-cleaned Kaggle dataset. Every step, from sourcing to the final dashboard, was built and debugged from scratch.

**[Add a dashboard screenshot or GIF here once exported]**

---

## Project Overview

Most "IPL analytics" portfolio projects reuse the same pre-flattened CSV from Kaggle. This project instead starts from [Cricsheet](https://cricsheet.org/)'s raw, nested per-match JSON archive — parsing, cleaning, and structuring the data into a relational schema myself, then analyzing it in PostgreSQL and visualizing it in Power BI.

**Scope:** 1,243 IPL matches (2008–2026), 295,732 ball-by-ball deliveries.

---

## At a Glance

| Metric | Value |
|---|---|
| Total matches | 1,243 |
| Total deliveries parsed | 295,732 |
| Seasons covered | 19 (2008–2026) |
| Total sixes | ~16,000 |
| Data quality issues found & fixed | 5 |
| Venues normalized | 27 → 22 |
| Teams normalized | 19 → 15 |

---

## Pipeline

**Raw data → Python parser → PostgreSQL → SQL analysis → Power BI dashboard**

1. **Sourced** Cricsheet's full match archive (22,734 matches across every format/league they track) and filtered to IPL matches only.
2. **Parsed** each match's raw JSON into two normalized tables (`matches`, `deliveries`) using a custom Python script.
3. **Loaded** into PostgreSQL.
4. **Analyzed** using SQL — phase-wise scoring, toss/venue impact, bowler death-over value.
5. **Visualized** in a 4-page Power BI dashboard.

---

## Data Quality Issues Found & Fixed

Working from raw data (rather than a pre-cleaned dataset) surfaced several real issues that would have silently corrupted the analysis if left unhandled:

| Issue | Problem | Fix |
|---|---|---|
| **Duplicate delivery labels** | Cricsheet labels a wide/no-ball retry with the same `over.ball` tag as the original delivery, which would corrupt over-based stats (economy, run rate) if used as a unique key | Built a separate running `legal_ball_number` counter that only increments on legal deliveries |
| **CSV import column mismatch** | The auto-increment `delivery_row_id` column was being included in the import wizard's column mapping, shifting every subsequent field by one | Excluded the auto-generated primary key from the column mapping |
| **Venue naming inconsistency** | The same physical ground appears under multiple names across seasons (e.g. "Wankhede Stadium" vs. "Wankhede Stadium, Mumbai") — this was silently splitting win-rate samples across duplicate rows | Normalized venue names via a reusable SQL view; verified each merge against real franchise/venue history rather than assuming string similarity implies identity |
| **Team naming (franchise renames vs. genuinely different franchises)** | Some name changes are true rebrands (Delhi Daredevils → Delhi Capitals); others only *look* similar but are legally distinct franchises (Gujarat Lions ≠ Gujarat Titans; Deccan Chargers ≠ Sunrisers Hyderabad, per BCCI's re-auction) | Researched actual franchise ownership history and merged only genuine renames, documented the judgment call explicitly |
| **Bowler economy overstated** | Initial economy calculation included byes/leg-byes in runs charged to the bowler, which isn't how cricket scores bowling economy | Corrected to only charge wides/no-balls to the bowler; re-ranked the death-over bowler analysis on the corrected figure |

---

## Key Findings

### 1. Death overs carry roughly double the dismissal risk for ~25% more reward
Across the full dataset, death overs (16–20) run at a **10.06 run rate** vs. 7.95–8.09 in the powerplay/middle overs — but the wicket rate roughly doubles in the same phase. Scoring aggressively at the death is a real trade-off, not a free lunch.

### 2. Toss-decision advantage looked venue-dependent — but statistical testing shows most of that spread isn't reliable
A naive read of the aggregate data suggests chasing wins more often (54% vs. 46%), and a first pass at venue-level breakdowns showed chase-win% ranging from 38.9% to 64.7% across venues — a 26-point spread that looked like strong evidence for venue-specific strategy.

**Testing this properly changes the conclusion.** Computing 95% Wilson confidence intervals for each venue (accounting for sample size) shows that **only one venue — Sawai Mansingh Stadium (68 matches, 64.71% chase-win rate, CI [52.8%, 75.0%]) — has a chase advantage that's statistically distinguishable from 50/50.** Every other venue's confidence interval overlaps 50%, meaning with the sample sizes available (many venues have fewer than 40–90 decisive matches), the apparent spread is largely consistent with sampling noise rather than a real venue effect.

**Corrected recommendation:** treat toss-decision strategy as broadly balanced league-wide, with Sawai Mansingh Stadium as a specific, statistically supported exception where bowling first is justified. Claiming a universal "venue-dependent strategy" from the raw percentages alone would have been an overclaim — a good example of why sample size matters before treating a descriptive difference as an actionable finding.

### 3. Raw economy rate is misleading without a baseline — and a real bowler value metric
JJ Bumrah's death-over economy (8.19) looks unremarkable in isolation, but against the death-over league average of ~10, that's **1.67 runs saved per over — over the largest sample of any bowler in the dataset (1,423 balls)**. SP Narine, better known as a powerplay spinner, actually tops the death-over value list, an intuition-defying result worth further investigation.

---

## Dashboard

4-page interactive Power BI dashboard, custom-themed (navy/cyan broadcast-graphics style, matching the sports domain):

- **Overview** — KPI cards (total matches, total deliveries, total sixes, seasons covered) as a landing summary
- **Phase-Wise Risk vs. Reward** — run rate & wicket rate by innings phase
- **Venue Strategy** — chase-win% by (normalized) venue, ranked
- **Death-Over Bowlers** — bowler value vs. league average, ranked

Pages are cross-linked with in-dashboard navigation buttons.

---

## Repo Structure

```
ipl-analytics/
├── README.md
├── etl/
│   ├── filter_ipl_matches.py     # filters Cricsheet's full archive to IPL matches
│   └── parse_ipl_matches.py      # parses raw JSON into normalized CSVs
├── sql/
│   ├── schema.sql                 # table definitions
│   ├── views.sql                  # matches_clean, bowler_death_stats
│   └── analysis_queries.sql       # phase-wise, venue, bowler queries
├── outputs/
│   └── (query result CSVs, dashboard screenshots)
```

*(Note: the raw Cricsheet archive and full deliveries table aren't included in this repo due to size — see [Data Source](#data-source) to regenerate them.)*

---

## Data Source

[Cricsheet](https://cricsheet.org/) — ball-by-ball cricket match data, freely available for non-commercial use with attribution. See their [terms](https://cricsheet.org/register/) for details.

---

## Tools

Python (parsing) · PostgreSQL (storage & analysis) · Power BI (dashboard)
