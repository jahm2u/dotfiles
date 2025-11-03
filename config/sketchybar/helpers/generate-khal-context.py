#!/usr/bin/env python3
"""
Generate one-time khal calendar context JSON for backfill.
60-day window: 30 days back + 30 days forward from today.

Author: Amelia (Dev Agent)
Date: 2025-11-03
"""

import json
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

# Output path
OUTPUT_FILE = Path.home() / ".cache/sketchybar/khal-context-60d.json"
OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)

def generate_khal_context():
    """Generate 60-day khal calendar context JSON"""

    print("Generating 60-day khal calendar context...")

    # Calculate 60-day window
    today = datetime.now()
    start_date = (today - timedelta(days=30)).strftime('%Y-%m-%d')

    print(f"Window: {start_date} + 60 days")

    try:
        # Query khal (may take ~5 minutes with large calendars)
        print("  Querying khal (this may take ~5 minutes)...")
        result = subprocess.run(
            ['khal', 'list', start_date, '60d', '--format', '{start-date} {start-time} | {title}'],
            capture_output=True,
            text=True,
            timeout=360  # 6 minutes timeout
        )

        if result.returncode != 0:
            print(f"ERROR: khal query failed: {result.stderr}")
            sys.exit(1)

        # Parse events
        events = []
        events_by_date = {}

        for line in result.stdout.strip().split('\n'):
            if not line or '|' not in line:
                continue

            try:
                date_time_part, title = line.split('|', 1)
                date_time_part = date_time_part.strip()
                title = title.strip()

                # Parse: "2024-10-20 14:30" or "2024-10-20"
                parts = date_time_part.split()
                date = parts[0] if len(parts) > 0 else None
                time = parts[1] if len(parts) > 1 else None

                if date:
                    event = {
                        'date': date,
                        'time': time,
                        'title': title
                    }
                    events.append(event)

                    # Group by date for fast lookup
                    if date not in events_by_date:
                        events_by_date[date] = []
                    events_by_date[date].append(event)

            except Exception as e:
                print(f"Warning: Failed to parse line: {line} - {str(e)}")
                continue

        # Build context object
        context = {
            'generated_at': datetime.now().isoformat(),
            'window_start': start_date,
            'window_days': 60,
            'total_events': len(events),
            'events': events,
            'events_by_date': events_by_date
        }

        # Save to JSON
        with open(OUTPUT_FILE, 'w') as f:
            json.dump(context, f, indent=2)

        print(f"\n✓ Generated khal context:")
        print(f"  - Total events: {len(events)}")
        print(f"  - Unique dates: {len(events_by_date)}")
        print(f"  - Saved to: {OUTPUT_FILE}")
        print(f"  - File size: {OUTPUT_FILE.stat().st_size / 1024:.1f} KB")

        # Show sample
        print(f"\nSample events:")
        for event in events[:5]:
            time_str = event['time'] or 'All-day'
            print(f"  - {event['date']} {time_str}: {event['title']}")

        return 0

    except subprocess.TimeoutExpired:
        print("ERROR: khal query timed out (>30s)")
        return 1
    except FileNotFoundError:
        print("ERROR: khal not found - ensure it's installed")
        return 1
    except Exception as e:
        print(f"ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == '__main__':
    sys.exit(generate_khal_context())
