# Cricsheet dumps every match they track into one giant folder (22k+ files,
# every format, every league). I only need IPL, so this script goes through
# each file, checks the event name, and copies the IPL ones into their own folder.
#
# Ran this in Colab on the unzipped all_json.zip from cricsheet.org/downloads

import json
import os
import shutil
from pathlib import Path
from collections import Counter

SOURCE_DIR = "all_json"       # wherever you unzipped everything
DEST_DIR = "ipl_matches"      # this is where the IPL-only files end up

def scan_and_filter():
    source = Path(SOURCE_DIR)
    dest = Path(DEST_DIR)
    dest.mkdir(exist_ok=True)

    if not source.exists():
        print(f"!! can't find '{SOURCE_DIR}' - check the path is right")
        return

    all_files = list(source.glob("*.json"))
    print(f"found {len(all_files)} match files, scanning now...\n")

    event_name_counts = Counter()
    match_type_counts = Counter()
    ipl_files = []
    unreadable_files = []

    for i, filepath in enumerate(all_files):
        # just a progress check so I know it's not frozen, this takes a while
        if i % 2000 == 0 and i > 0:
            print(f"  ...done {i}/{len(all_files)}")

        try:
            with open(filepath, "r", encoding="utf-8") as f:
                data = json.load(f)
        except (json.JSONDecodeError, UnicodeDecodeError) as e:
            # a couple of files threw errors when I first ran this,
            # so logging them instead of letting the whole thing crash
            unreadable_files.append((filepath.name, str(e)))
            continue

        info = data.get("info", {})
        event = info.get("event", {})
        event_name = event.get("name", "UNKNOWN")
        match_type = info.get("match_type", "UNKNOWN")

        event_name_counts[event_name] += 1
        match_type_counts[match_type] += 1

        # this is the actual filter - checked a few sample files first and
        # confirmed IPL matches all have this exact string in event.name
        if "Indian Premier League" in event_name:
            ipl_files.append(filepath)

    print(f"\ndone scanning. {len(ipl_files)} IPL matches out of {len(all_files)} total.")

    if unreadable_files:
        print(f"\n{len(unreadable_files)} files wouldn't parse:")
        for name, err in unreadable_files[:5]:
            print(f"   {name}: {err}")

    # printing this out mainly as a sanity check - wanted to make sure
    # "Indian Premier League" wasn't showing up under some slightly
    # different name in a few seasons (it wasn't, but good to check)
    print("\ntop 15 event names found:")
    for name, count in event_name_counts.most_common(15):
        print(f"   {count:5d}  {name}")

    print("\nmatch type breakdown:")
    for mtype, count in match_type_counts.most_common():
        print(f"   {count:5d}  {mtype}")

    print(f"\ncopying {len(ipl_files)} IPL files over to '{DEST_DIR}'...")
    for filepath in ipl_files:
        shutil.copy(filepath, dest / filepath.name)

    print("done - IPL matches are now in the ipl_matches folder")

if __name__ == "__main__":
    scan_and_filter()
