# Turns the raw per-match JSON files into two flat CSVs I can actually load
# into a database - matches.csv and deliveries.csv.
#
# The annoying part of this was figuring out how Cricsheet labels deliveries.
# Every ball has an "over.ball" label like "12.4", but if that ball is a wide
# or no-ball, it doesn't count as a legal delivery - so the NEXT ball reuses
# the same label. Found this out the hard way by eyeballing a raw file and
# noticing "30.2" showed up twice in a row. If I'd used that label as a unique
# id for anything (like counting balls per over), it would've been wrong.
# So instead I track my own counter (legal_ball_number) that only goes up
# when the delivery is actually legal.

import json
import csv
from pathlib import Path

SOURCE_DIR = "ipl_matches"          # the filtered folder from the last script
OUTPUT_DIR = "csv_output"


def parse_all_matches():
    source = Path(SOURCE_DIR)
    output = Path(OUTPUT_DIR)
    output.mkdir(exist_ok=True, parents=True)

    files = sorted(source.glob("*.json"))
    print(f"parsing {len(files)} IPL matches...\n")

    match_rows = []
    delivery_rows = []

    # keeping track of weird stuff I hit while parsing so I can check it later
    issues = {
        "missing_outcome": 0,
        "missing_toss": 0,
        "no_result_matches": 0,
        "files_failed": [],
    }

    for filepath in files:
        match_id = filepath.stem  # e.g. "1167108" from "1167108.json"

        try:
            with open(filepath, "r", encoding="utf-8") as f:
                data = json.load(f)
        except (json.JSONDecodeError, UnicodeDecodeError) as e:
            issues["files_failed"].append((filepath.name, str(e)))
            continue

        info = data.get("info", {})
        teams = info.get("teams", [None, None])
        outcome = info.get("outcome", {})
        toss = info.get("toss", {})

        # some matches are no-result / abandoned / tied, so there's no clean
        # "winner" field - need to not crash on those, just record what's there
        winner = outcome.get("winner")
        win_by = outcome.get("by", {})
        win_by_runs = win_by.get("runs")
        win_by_wickets = win_by.get("wickets")
        if not winner:
            issues["missing_outcome"] += 1
            if "result" in outcome:
                issues["no_result_matches"] += 1

        if not toss:
            issues["missing_toss"] += 1

        match_rows.append({
            "match_id": match_id,
            "date": info.get("dates", [None])[0],
            "season": info.get("season"),
            "team1": teams[0] if len(teams) > 0 else None,
            "team2": teams[1] if len(teams) > 1 else None,
            "venue": info.get("venue"),
            "city": info.get("city"),
            "toss_winner": toss.get("winner"),
            "toss_decision": toss.get("decision"),
            "winner": winner,
            "win_by_runs": win_by_runs,
            "win_by_wickets": win_by_wickets,
            "player_of_match": (info.get("player_of_match") or [None])[0],
        })

        # now the ball-by-ball part
        for inning_idx, inning in enumerate(data.get("innings", []), start=1):
            batting_team = inning.get("team")
            legal_ball_counter = 0  # this is the fix for the wide/no-ball label issue

            for over_block in inning.get("overs", []):
                over_num = over_block.get("over")

                for delivery in over_block.get("deliveries", []):
                    extras = delivery.get("extras", {})
                    is_wide = "wides" in extras
                    is_noball = "noballs" in extras
                    is_legal = not (is_wide or is_noball)

                    if is_legal:
                        legal_ball_counter += 1

                    runs = delivery.get("runs", {})
                    wickets = delivery.get("wickets", [])

                    extras_type = None
                    if extras:
                        extras_type = next(iter(extras.keys()), None)

                    delivery_rows.append({
                        "match_id": match_id,
                        "innings_number": inning_idx,
                        "batting_team": batting_team,
                        "over_number": over_num,
                        "legal_ball_number": legal_ball_counter if is_legal else None,
                        "is_legal_delivery": is_legal,
                        "actual_delivery_label": delivery.get("actual_delivery"),
                        "batter": delivery.get("batter"),
                        "bowler": delivery.get("bowler"),
                        "non_striker": delivery.get("non_striker"),
                        "runs_batter": runs.get("batter", 0),
                        "runs_extras": runs.get("extras", 0),
                        "runs_total": runs.get("total", 0),
                        "extras_type": extras_type,
                        "is_wicket": len(wickets) > 0,
                        "player_out": wickets[0].get("player_out") if wickets else None,
                        "wicket_kind": wickets[0].get("kind") if wickets else None,
                    })

    # write matches.csv
    matches_path = output / "matches.csv"
    with open(matches_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=match_rows[0].keys())
        writer.writeheader()
        writer.writerows(match_rows)

    # write deliveries.csv
    deliveries_path = output / "deliveries.csv"
    with open(deliveries_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=delivery_rows[0].keys())
        writer.writeheader()
        writer.writerows(delivery_rows)

    print(f"parsed {len(match_rows)} matches, {len(delivery_rows)} deliveries\n")
    print(f"matches.csv -> {matches_path}")
    print(f"deliveries.csv -> {deliveries_path}\n")

    # sanity check output so I know if anything looks off before loading into SQL
    print("quick data quality check:")
    print(f"  matches with no winner (no-result/tie): {issues['missing_outcome']}")
    print(f"  matches missing toss info: {issues['missing_toss']}")
    if issues["files_failed"]:
        print(f"  files that failed to parse: {len(issues['files_failed'])}")
        for name, err in issues["files_failed"][:5]:
            print(f"    {name}: {err}")
    else:
        print("  no files failed to parse - good sign")


if __name__ == "__main__":
    parse_all_matches()
