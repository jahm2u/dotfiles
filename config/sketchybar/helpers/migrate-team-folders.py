#!/usr/bin/env python3
"""
Obsidian Team Folder Migration Script
Consolidates team folders from old locations to: Business/IPMedia/Teams/

Author: Claude
Date: 2025-11-11
Purpose: Fix fragmented team meeting data across 3 locations
"""

import os
import sys
import shutil
from pathlib import Path
from datetime import datetime

# Load vault path from env
vault_path = os.getenv("OBSIDIAN_VAULT_PATH")
if not vault_path or not os.path.exists(vault_path):
    print("ERROR: OBSIDIAN_VAULT_PATH not set or invalid")
    sys.exit(1)

vault = Path(vault_path)

# Define locations
CORRECT_LOCATION = vault / "Business/IPMedia/Teams"
OLD_LOCATION_1 = vault / "Business/Teams"
OLD_LOCATION_2 = vault / "Business/People/IPMedia/Teams"

# Team name normalization mapping (handle case inconsistencies)
TEAM_NAME_MAP = {
    'bi': 'Bi',
    'BI': 'Bi',
    'hr': 'Hr',
    'Hr': 'Hr',
    'marketing': 'Marketing',
    'product': 'Product',
    'development': 'Development',
    'operations': 'Operations',
    'leadership': 'Leadership',
    'traffic': 'Traffic',
    'it-infrastructure': 'IT-Infrastructure',
    'marketing-infrastructure': 'Marketing-Infrastructure',
}

def normalize_team_name(name):
    """Normalize team name for consistency"""
    name_lower = name.lower()
    return TEAM_NAME_MAP.get(name_lower, name)

def analyze_locations():
    """Analyze what exists in each location"""
    print("=== ANALYZING TEAM FOLDERS ===\n")

    analysis = {}

    for location_name, location_path in [
        ("Business/Teams (OLD)", OLD_LOCATION_1),
        ("Business/People/IPMedia/Teams (OLD)", OLD_LOCATION_2),
        ("Business/IPMedia/Teams (CORRECT)", CORRECT_LOCATION)
    ]:
        print(f"{location_name}:")
        if not location_path.exists():
            print("  (does not exist)\n")
            continue

        for item in sorted(location_path.iterdir()):
            if not item.is_dir():
                print(f"  {item.name} (FILE - will skip)")
                continue

            normalized = normalize_team_name(item.name)
            meetings_dir = item / "Meetings"
            meeting_count = 0

            if meetings_dir.exists():
                meeting_files = list(meetings_dir.glob("*.md"))
                meeting_count = len(meeting_files)

            print(f"  {item.name} → {normalized}: {meeting_count} meetings")

            # Track for migration
            if normalized not in analysis:
                analysis[normalized] = []
            analysis[normalized].append({
                'source_path': item,
                'location': location_name,
                'meeting_count': meeting_count,
                'original_name': item.name
            })
        print()

    return analysis

def create_migration_plan(analysis):
    """Create migration plan with conflict resolution"""
    print("=== MIGRATION PLAN ===\n")

    plan = []

    for team_name, sources in sorted(analysis.items()):
        if team_name == 'Gone':
            print(f"{team_name}: SKIP (portfolio company, should be in Business/Company/)")
            continue

        if team_name in ['attachments', 'Teams.md']:
            print(f"{team_name}: SKIP (not a team folder)")
            continue

        # Check if team already exists in correct location
        target = CORRECT_LOCATION / team_name
        sources_in_correct = [s for s in sources if 'CORRECT' in s['location']]
        sources_in_old = [s for s in sources if 'CORRECT' not in s['location']]

        if sources_in_correct and sources_in_old:
            # Merge scenario
            total_meetings = sum(s['meeting_count'] for s in sources)
            print(f"{team_name}: MERGE {len(sources)} locations ({total_meetings} total meetings)")
            for s in sources:
                print(f"  - {s['location']}: {s['meeting_count']} meetings")

            plan.append({
                'action': 'merge',
                'team': team_name,
                'target': target,
                'sources': sources
            })

        elif sources_in_old:
            # Move scenario
            total_meetings = sum(s['meeting_count'] for s in sources_in_old)
            print(f"{team_name}: MOVE from old location(s) ({total_meetings} meetings)")
            for s in sources_in_old:
                print(f"  - {s['location']}: {s['meeting_count']} meetings")

            plan.append({
                'action': 'move',
                'team': team_name,
                'target': target,
                'sources': sources_in_old
            })
        else:
            print(f"{team_name}: ALREADY IN CORRECT LOCATION ({sources_in_correct[0]['meeting_count']} meetings)")

    print()
    return plan

def execute_migration(plan, dry_run=True):
    """Execute migration plan"""
    mode = "DRY RUN" if dry_run else "EXECUTING"
    print(f"=== {mode} MIGRATION ===\n")

    # Create backup dir
    backup_dir = vault / f".migration-backup-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    if not dry_run:
        backup_dir.mkdir(exist_ok=True)
        print(f"Backup directory: {backup_dir}\n")

    for item in plan:
        team = item['team']
        target = item['target']
        action = item['action']

        print(f"Team: {team} ({action.upper()})")

        if action == 'move':
            # Simple move - no conflicts
            for source_info in item['sources']:
                source = source_info['source_path']
                print(f"  Moving: {source.relative_to(vault)} → {target.relative_to(vault)}")

                if not dry_run:
                    # Create target if doesn't exist
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.move(str(source), str(target))

        elif action == 'merge':
            # Complex merge - need to consolidate meetings
            sources_to_merge = [s for s in item['sources'] if 'CORRECT' not in s['location']]

            for source_info in sources_to_merge:
                source = source_info['source_path']
                source_meetings = source / "Meetings"
                target_meetings = target / "Meetings"

                if not source_meetings.exists():
                    print(f"  Skipping {source.relative_to(vault)} (no Meetings folder)")
                    continue

                print(f"  Merging meetings from: {source.relative_to(vault)}")

                if not dry_run:
                    # Ensure target Meetings folder exists
                    target_meetings.mkdir(parents=True, exist_ok=True)

                    # Move each meeting file
                    for meeting_file in source_meetings.glob("*.md"):
                        target_file = target_meetings / meeting_file.name

                        if target_file.exists():
                            # Conflict - rename with source location suffix
                            backup_name = f"{meeting_file.stem}-from-{source.name}{meeting_file.suffix}"
                            target_file = target_meetings / backup_name
                            print(f"    ⚠ Conflict: {meeting_file.name} → {backup_name}")

                        shutil.move(str(meeting_file), str(target_file))
                        print(f"    ✓ Moved: {meeting_file.name}")

                    # Backup and remove old source folder
                    backup_source = backup_dir / source.relative_to(vault)
                    backup_source.parent.mkdir(parents=True, exist_ok=True)
                    shutil.move(str(source), str(backup_source))
                    print(f"    Backed up source to: {backup_source.relative_to(vault)}")

        print()

    print(f"{'Would complete' if dry_run else 'Completed'} migration of {len(plan)} teams\n")

def main():
    import argparse

    parser = argparse.ArgumentParser(description='Migrate team folders to correct location')
    parser.add_argument('--execute', action='store_true', help='Actually perform migration (default is dry-run)')
    args = parser.parse_args()

    # Analyze current state
    analysis = analyze_locations()

    # Create migration plan
    plan = create_migration_plan(analysis)

    if not plan:
        print("No migration needed - all teams already in correct location!")
        return

    # Execute (or dry-run)
    execute_migration(plan, dry_run=not args.execute)

    if not args.execute:
        print("=== DRY RUN COMPLETE ===")
        print("Run with --execute to perform actual migration")
        print("WARNING: Make sure Obsidian is closed before executing!")

if __name__ == '__main__':
    main()
