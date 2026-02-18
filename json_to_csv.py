#!/usr/bin/env python3
"""Convert infusion-tracker JSON backup to SiteCycle CSV export format."""

import argparse
import csv
import datetime
import json
import sys
from pathlib import Path


NAME_MAP = {
    "Butt": "Buttock",
}


def to_zone_name(name):
    """Convert JSON "Body - qualifier" format to SiteCycle "Qualifier Body" zone format."""
    name = NAME_MAP.get(name, name)
    if ' - ' in name:
        body, qualifier = name.split(' - ', 1)
        return f"{qualifier.title()} {body.title()}"
    return name.title()


def format_location(site):
    prefix = 'Left' if site['side'] == 'left' else 'Right'
    return f"{prefix} {to_zone_name(site['name'])}"


def ms_to_iso8601(ts_ms):
    dt = datetime.datetime.fromtimestamp(ts_ms / 1000, tz=datetime.timezone.utc)
    return dt.strftime('%Y-%m-%dT%H:%M:%SZ')


def main():
    parser = argparse.ArgumentParser(
        description="Convert infusion-tracker JSON backup to SiteCycle CSV format."
    )
    parser.add_argument("input", type=Path, help="Path to the JSON backup file")
    parser.add_argument(
        "output",
        type=Path,
        nargs="?",
        help="Path for the output CSV file (default: sitecycle-export-<date>.csv alongside input)",
    )
    args = parser.parse_args()

    input_file: Path = args.input
    if args.output:
        output_file: Path = args.output
    else:
        date_str = datetime.date.today().strftime("%Y-%m-%d")
        output_file = input_file.parent / f"sitecycle-export-{date_str}.csv"

    with input_file.open() as f:
        data = json.load(f)

    if 'sites' not in data or 'usageHistory' not in data:
        print("Error: JSON missing 'sites' or 'usageHistory' keys", file=sys.stderr)
        sys.exit(1)

    site_map = {site['id']: site for site in data['sites']}
    history = sorted(data['usageHistory'], key=lambda e: e['timestamp'])

    rows = []
    for i, entry in enumerate(history):
        site = site_map.get(entry['siteId'])
        if site is None:
            print(f"Warning: siteId {entry['siteId']} not found, skipping", file=sys.stderr)
            continue

        is_last = (i == len(history) - 1)
        if is_last:
            duration_hours = ''
        else:
            delta_ms = history[i + 1]['timestamp'] - entry['timestamp']
            duration_hours = f"{delta_ms / 3_600_000:.1f}"

        rows.append({
            'date': ms_to_iso8601(entry['timestamp']),
            'location': format_location(site),
            'duration_hours': duration_hours,
            'note': '',
        })

    with output_file.open('w', newline='') as f:
        writer = csv.DictWriter(
            f,
            fieldnames=['date', 'location', 'duration_hours', 'note'],
            quoting=csv.QUOTE_MINIMAL,
            lineterminator='\n',
        )
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {len(rows)} rows to {output_file}")


if __name__ == '__main__':
    main()
