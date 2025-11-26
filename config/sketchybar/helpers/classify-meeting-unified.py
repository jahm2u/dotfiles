#!/usr/bin/env python3
"""
Unified Meeting Classification with Calendar Matching
A single source of truth for meeting classification across all scripts.

This script provides consistent meeting classification by:
1. First attempting to match with calendar events (most accurate)
2. Falling back to pattern matching if no calendar match found
3. Applying email-to-name mappings for participant identification

Used by:
- meeting-prep.sh (when clicking meeting icon)
- krisp processing pipeline (for downloaded transcripts)
- any other script needing meeting classification

Author: Claude (unifying John's work)
Date: 2025-11-10
"""

import argparse
import json
import re
import subprocess
import sys
import os
from datetime import datetime, timedelta
from pathlib import Path

# Month name to number mapping
MONTH_MAP = {
    'january': 1, 'jan': 1,
    'february': 2, 'feb': 2,
    'march': 3, 'mar': 3,
    'april': 4, 'apr': 4,
    'may': 5,
    'june': 6, 'jun': 6,
    'july': 7, 'jul': 7,
    'august': 8, 'aug': 8,
    'september': 9, 'sep': 9, 'sept': 9,
    'october': 10, 'oct': 10,
    'november': 11, 'nov': 11,
    'december': 12, 'dec': 12
}

# Known company mapping for Discord/external meetings
PARTICIPANT_COMPANY_MAP = {
    'dannniboy': 'DT',
    'danniboy': 'DT',
    'chris': 'MT',
    'nima': 'CO',  # Cross-organization
    'kyle': 'CO',
}


def log(message, level="INFO"):
    """Log to stderr to avoid contaminating JSON output"""
    print(f"[{level}] {message}", file=sys.stderr)


def load_email_name_map():
    """Load email to Obsidian name mapping from config file."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    map_file = os.path.join(script_dir, "email-name-map.txt")

    email_map = {}
    if os.path.exists(map_file):
        with open(map_file, 'r') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                if '=' in line:
                    email, name = line.split('=', 1)
                    email_map[email.strip().lower()] = name.strip()

    return email_map


def query_calendar_events(date_str):
    """
    Query khal for events on specified date.
    Returns list of events with start_time and title.
    """
    try:
        # Use khal to get events for the date
        result = subprocess.run(
            ['khal', 'list', date_str, '1d', '--format', '{start-time} | {title}'],
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode != 0:
            log(f"khal query failed: {result.stderr}", "ERROR")
            return []

        events = []
        for line in result.stdout.strip().split('\n'):
            if not line or '|' not in line:
                continue

            parts = line.split('|', 1)
            if len(parts) == 2:
                start_time_raw = parts[0].strip()
                title = parts[1].strip()

                # Convert khal's 12-hour format (08:00 AM) to 24-hour format (08:00)
                try:
                    if 'AM' in start_time_raw or 'PM' in start_time_raw:
                        time_obj = datetime.strptime(start_time_raw, "%I:%M %p")
                        start_time_24h = time_obj.strftime("%H:%M")
                    else:
                        start_time_24h = start_time_raw

                    events.append({
                        'start_time': start_time_24h,
                        'title': title
                    })
                except ValueError:
                    # If parsing fails, skip this event
                    log(f"Failed to parse time '{start_time_raw}'", "WARN")
                    continue

        log(f"Found {len(events)} calendar events for {date_str}", "INFO")
        return events

    except subprocess.TimeoutExpired:
        log("khal query timed out", "ERROR")
    except FileNotFoundError:
        log("khal not found - install with: brew install khal", "ERROR")
    except Exception as e:
        log(f"Calendar query error: {e}", "ERROR")

    return []


def match_with_calendar(title, date, time_str=None):
    """
    Try to match a meeting title/time with actual calendar events.
    Returns the best matching calendar event or None.
    """
    if not date:
        return None

    # Query calendar for the date
    events = query_calendar_events(date)
    if not events:
        return None

    # Initialize time_24h to None (may be set below if time_str provided)
    time_24h = None

    # If we have a specific time, try to match it
    if time_str:
        # Convert to 24h format for comparison
        try:
            time_obj = datetime.strptime(time_str, "%I:%M %p")
            time_24h = time_obj.strftime("%H:%M")
        except:
            time_24h = None

        if time_24h:
            # Look for exact time match first
            for event in events:
                if event['start_time'] == time_24h:
                    log(f"Exact calendar match: {event['title']}", "INFO")
                    return event

            # Look for close time match (within 15 minutes - meetings often start late)
            # Collect all matches and prefer more important meetings
            matches = []
            for event in events:
                try:
                    event_time = datetime.strptime(event['start_time'], "%H:%M")
                    target_time = datetime.strptime(time_24h, "%H:%M")
                    diff = abs((event_time - target_time).total_seconds() / 60)
                    if diff <= 15:
                        matches.append((diff, event))
                except:
                    continue

            if matches:
                # If multiple matches at same time, prefer by priority:
                # 1. Internal Meeting / Board / Company-wide (highest priority)
                # 2. 1on1s
                # 3. Team meetings
                # 4. Everything else
                def event_priority(event_tuple):
                    diff, event = event_tuple
                    title_lower = event['title'].lower()

                    # Priority 1: Company-wide meetings
                    if any(kw in title_lower for kw in ['internal meeting', 'board meeting', 'company-wide', 'all hands', 'quarterly', 'monthly']):
                        return (0, diff)  # Highest priority
                    # Priority 2: 1on1s
                    elif any(kw in title_lower for kw in ['1on1', '1:1', '<>']):
                        return (1, diff)
                    # Priority 3: Team meetings
                    elif any(kw in title_lower for kw in ['team', 'meeting', 'weekly', 'sync']):
                        return (2, diff)
                    # Priority 4: Everything else
                    else:
                        return (3, diff)

                best_match = min(matches, key=event_priority)
                log(f"Close calendar match (±{int(best_match[0])}min): {best_match[1]['title']}", "INFO")
                return best_match[1]

    # If no time match within 15 min, try relaxed matching (within 30 min)
    # but ONLY for events that also have platform hints
    if time_24h:
        title_lower = title.lower()
        for event in events:
            try:
                event_time = datetime.strptime(event['start_time'], "%H:%M")
                target_time = datetime.strptime(time_24h, "%H:%M")
                diff = abs((event_time - target_time).total_seconds() / 60)

                # Within 30 min AND has platform/pattern hint
                if diff <= 30:
                    event_title_lower = event['title'].lower()
                    has_hint = (
                        ('slack' in title_lower and 'slack' in event_title_lower) or
                        ('discord' in title_lower and ('discord' in event_title_lower or '1:1' in event_title_lower or '1on1' in event_title_lower)) or
                        ('zoom' in title_lower and 'zoom' in event_title_lower)
                    )
                    if has_hint:
                        log(f"Relaxed calendar match (±{int(diff)}min + platform hint): {event['title']}", "INFO")
                        return event
            except:
                continue

    return None


def extract_participant_from_title(title, user_names=['jeff', 'hamersly']):
    """
    Extract participant name from meeting title, filtering out the user.

    Handles patterns like:
    - "Jeff <> Giovanna" → "Giovanna"
    - "Vlad & Jeff" → "Vlad"
    - "1on1 Thais Jeff" → "Thais"
    - "Follow-up APM Position Jeff <> Giovanna" → "Giovanna"
    """
    # Pattern 1: "<>" separator
    match = re.search(r'([^<]+)\s*<>\s*(.+)', title)
    if match:
        left = match.group(1).strip()
        right = match.group(2).strip()

        # Extract just the names (usually last word on left, first word on right)
        left_words = left.split()
        right_words = right.split()

        # Take last word from left side, first word from right side
        left_name = left_words[-1] if left_words else ""
        right_name = right_words[0] if right_words else ""

        # Return the one that isn't the user
        if right_name.lower() not in user_names and right_name:
            return right_name  # Prefer right side first
        if left_name.lower() not in user_names and left_name:
            return left_name

    # Pattern 2: "&" separator
    match = re.search(r'(.+?)\s+&\s+(.+?)(?:\s+moving forward)?', title, re.IGNORECASE)
    if match:
        left = match.group(1).strip().split()[-1]  # Take last word
        right = match.group(2).strip().split()[0]   # Take first word

        if left.lower() not in user_names:
            return left
        if right.lower() not in user_names:
            return right

    # Pattern 3: "1on1 Name1 Name2"
    match = re.search(r'1on1\s+(\w+)(?:\s+(\w+))?', title, re.IGNORECASE)
    if match:
        name1 = match.group(1)
        name2 = match.group(2) if match.group(2) else None

        if name1.lower() not in user_names:
            return name1
        if name2 and name2.lower() not in user_names:
            return name2

    # Pattern 4: "1:1 with Name" or "1on1 with Name"
    match = re.search(r'1[:o]1\s+with\s+(\w+)', title, re.IGNORECASE)
    if match:
        return match.group(1)

    return None


def extract_team_from_title(title):
    """
    Extract specific team name from meeting title.
    Returns tuple of (category, subcategory) or (category, None).

    Categories:
    - team: Regular team meetings (Leadership, Operations, etc.)
    - marketing: Marketing sub-teams (traffic, social_pr, seo)
    - dev: Development squads (growth, meumatch, slackbot, marcus)
    """
    title_lower = title.lower()

    # Team-specific patterns (order matters - most specific first)
    team_patterns = [
        # Leadership team (Internal Meeting is company-wide, not team)
        (r'headquarters?\s+meeting|(?<!internal\s)leadership', ('team', 'Leadership')),

        # BI team
        (r'bi\s+meeting', ('team', 'BI')),

        # SUPORTE team (Ops/Support team) - check before HR since "RH <> SUPORTE" should be SUPORTE
        (r'suporte', ('team', 'Suporte')),

        # HR team (but not slackbot - that's a dev squad now)
        (r'\bhr\b|recruitment|rh\b', ('team', 'Hr')),

        # Operations team
        (r'ops\s+team|operations', ('team', 'Operations')),

        # Development squads (ipmedia_dev_*)
        (r'growth\s+squad|growth\s+team|\bgrowth\b', ('dev', 'growth')),
        (r'meumatch', ('dev', 'meumatch')),
        (r'slackbot\s*weekly', ('dev', 'slackbot')),
        (r'dev\s+squad|weekly\s+dev\s+squad', ('dev', 'marcus')),  # Generic dev squad = Marcus's squad

        # Marketing sub-teams (ipmedia_marketing_*)
        (r'traffic\s+weekly', ('marketing', 'traffic')),
        (r'social\s+media.*press|press.*social|social\s+media.*headquarters', ('marketing', 'social_pr')),
        (r'\bseo\b|meu\s+patrocinio.*seo|seo.*meu\s+patrocinio', ('marketing', 'seo')),
        (r'mkt\b|marketing|mkt\s+headquarter', ('marketing', None)),  # Generic marketing

        # Product team (general product, not squads)
        (r'product\s+team|mp\s+product', ('team', 'Product')),

        # IT Infrastructure
        (r'it[-\s]infrastructure|infrastructure', ('team', 'IT-Infrastructure')),
    ]

    for pattern, result in team_patterns:
        if re.search(pattern, title_lower):
            return result

    return None


def extract_portfolio_company(title):
    """
    Extract portfolio company code from meeting title.
    Returns company code or None.
    """
    title_lower = title.lower()

    # Portfolio company patterns
    company_patterns = [
        (r'\btp\b|thierry\s+paul|weekly\s+meeting\s+tp', 'TP'),
        (r'excelsior|weekly\s+meeting\s+excelsior', 'Excelsior'),
        (r'\bpd\b|best\s+meeting\s+ever', 'PD'),
        (r'masstraffic|mt\s+weekly', 'MT'),
        (r'gone.*(?:weekly|sync)(?!.*standup)', 'Gone'),  # Gone company meetings (not standup)
        (r'jeff\s+and\s+dboy|dboy|danniboy|danniiboy|\bdt\b', 'DT'),  # DT company with Daniel/DBoy
        (r'\[co\]|cross[-\s]org', 'CO'),
    ]

    for pattern, company_code in company_patterns:
        if re.search(pattern, title_lower):
            return company_code

    return None


def classify_from_calendar_title(title):
    """
    Classify a meeting based on calendar title (more reliable than Krisp titles).
    Returns dict with meeting_type, company, participant, team.
    """
    title_lower = title.lower()
    result = {
        'meeting_type': 'unknown',
        'company': None,
        'participant': None,
        'team': None,
        'confidence': 0
    }

    # EXCLUSION LIST: Skip non-meetings (lunch, breaks, focus time, etc.)
    exclusion_patterns = [
        r'\blunch\b', r'\bbreak\b', r'\bfocus time\b', r'\bblocked\b',
        r'\bhold\b', r'\breserved\b', r'\bOOO\b',
        r'\bout of office\b', r'\bvacation\b', r'\bPTO\b',
        r'remote\s+cowork'  # In-person cowork sessions
    ]
    if any(re.search(pattern, title, re.IGNORECASE) for pattern in exclusion_patterns):
        result['meeting_type'] = 'excluded'
        result['confidence'] = 1.0
        return result

    # Check for Q4/Quarterly Reviews (person reviews - special handling)
    review_match = re.search(r'(?:q4|quarterly|q[1-4])\s+review.*[-–]\s*(\w+)|review.*q[1-4].*[-–]\s*(\w+)', title, re.IGNORECASE)
    if review_match:
        person = review_match.group(1) or review_match.group(2)
        result['meeting_type'] = 'ipmedia_review'
        result['company'] = 'IPMedia'
        result['participant'] = person
        result['confidence'] = 0.95
        return result

    # Check for Onboarding/Welcome meetings
    welcome_match = re.search(r'welcome\s+(?:by\s+jeff\s*>?\s*)?(\w+)|onboarding.*(\w+)', title, re.IGNORECASE)
    if welcome_match:
        person = welcome_match.group(1) or welcome_match.group(2)
        result['meeting_type'] = 'ipmedia_onboarding'
        result['company'] = 'IPMedia'
        result['participant'] = person
        result['confidence'] = 0.95
        return result

    # Check for Executive meetings (Ron - has special .meeting-config.json with cross-meeting context)
    if re.search(r'\bron\b.*\bweekly\b|\bweekly\b.*\bron\b|jeff\s*/\s*ron', title, re.IGNORECASE):
        result['meeting_type'] = 'ipmedia_executive'
        result['company'] = 'IPMedia'
        result['participant'] = 'Ron'
        result['confidence'] = 0.95
        return result

    # Check for Board meetings (monthly investor meetings)
    if re.search(r'board\s+meeting|monthly\s+board', title, re.IGNORECASE):
        result['meeting_type'] = 'ipmedia_board'
        result['company'] = 'IPMedia'
        result['confidence'] = 0.95
        return result

    # Check for KPI meetings (company-wide product health reviews)
    if re.search(r'\bkpi\b', title, re.IGNORECASE):
        result['meeting_type'] = 'ipmedia_company_wide'  # KPI goes with company-wide
        result['company'] = 'IPMedia'
        result['confidence'] = 0.95
        return result

    # Check for portfolio company meetings BEFORE team extraction
    portfolio_company = extract_portfolio_company(title)
    if portfolio_company:
        result['meeting_type'] = f'co_{portfolio_company.lower()}_meeting'
        result['company'] = portfolio_company
        result['confidence'] = 0.85
        return result

    # Check for external personal meetings (Vlad, etc.)
    if re.search(r'vlad\s*&\s*jeff|vlad.*moving\s+forward', title, re.IGNORECASE):
        result['meeting_type'] = 'external_personal'
        result['company'] = 'External'
        result['participant'] = 'Vlad'
        result['confidence'] = 0.9
        return result

    # Check for team/squad/marketing meetings
    team_result = extract_team_from_title(title)
    if team_result:
        category, subcategory = team_result

        if category == 'team':
            result['meeting_type'] = f'ipmedia_team_{subcategory.lower()}'
            result['team'] = subcategory
        elif category == 'dev':
            result['meeting_type'] = f'ipmedia_dev_{subcategory}'
            result['team'] = f'Dev-{subcategory.title()}'
        elif category == 'marketing':
            if subcategory:
                result['meeting_type'] = f'ipmedia_marketing_{subcategory}'
                result['team'] = f'Marketing-{subcategory.title()}'
            else:
                result['meeting_type'] = 'ipmedia_team_marketing'
                result['team'] = 'Marketing'

        result['company'] = 'IPMedia'
        result['confidence'] = 0.85
        return result

    # Check for 1-on-1 patterns (AFTER team check)
    one_on_one_indicators = [
        r'1:1', r'1on1', r'1-on-1',
        r'<>', r'\s&\s'  # Separators indicating 1-on-1
    ]
    is_one_on_one = any(re.search(pattern, title, re.IGNORECASE) for pattern in one_on_one_indicators)

    if is_one_on_one:
        result['meeting_type'] = 'ipmedia_1on1'
        result['company'] = 'IPMedia'
        result['participant'] = extract_participant_from_title(title)
        result['confidence'] = 0.9 if result['participant'] else 0.5
        return result

    # Check for standup meetings
    standup_patterns = [r'standup', r'stand-up', r'stand up', r'daily', r'scrum']
    if any(re.search(pattern, title, re.IGNORECASE) for pattern in standup_patterns):
        result['meeting_type'] = 'ipmedia_standup'
        result['company'] = 'IPMedia'
        result['confidence'] = 0.9
        return result

    # Check for company-wide meetings
    # Includes: All Hands, Company-Wide, Internal Meeting, Overview/Novembro
    if re.search(r'all\s+hands|company(?:\s+wide)?|internal\s+meeting|overview.*\d{4}|overview.*(?:janeiro|fevereiro|março|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro)', title, re.IGNORECASE):
        result['meeting_type'] = 'ipmedia_company_wide'
        result['company'] = 'IPMedia'
        result['confidence'] = 0.8
        return result

    # If nothing matched, return unknown (will use unclassified folder)
    result['confidence'] = 0
    return result


def classify_from_krisp_title(title):
    """
    Fallback classification from Krisp title alone (less accurate).
    """
    title_lower = title.lower()
    result = {
        'meeting_type': 'unknown',
        'company': None,
        'participant': None,
        'confidence': 0.3
    }

    # Platform gives hints
    if 'discord' in title_lower:
        # Discord usually means external/CO meetings
        result['meeting_type'] = 'one-on-one'
        result['company'] = 'CO'

        # Try to infer participant from known mappings
        for name, company in PARTICIPANT_COMPANY_MAP.items():
            if name in title_lower:
                result['participant'] = name.capitalize()
                result['company'] = company
                result['confidence'] = 0.6
                break

    elif 'slack' in title_lower:
        # Slack is usually internal IPMedia
        result['company'] = 'IPMedia'
        result['confidence'] = 0.5

    return result


def main():
    parser = argparse.ArgumentParser(description='Unified meeting classification')
    parser.add_argument('--title', required=True, help='Meeting title (from Krisp or calendar)')
    parser.add_argument('--date', help='Meeting date (YYYY-MM-DD)')
    parser.add_argument('--time', help='Meeting time (HH:MM AM/PM)')
    parser.add_argument('--participants', help='Comma-separated participant emails')
    parser.add_argument('--year', help='Year if date not provided')
    parser.add_argument('--month', help='Month if date not provided')
    parser.add_argument('--day', help='Day if date not provided')

    args = parser.parse_args()

    # Construct date if provided as components
    if not args.date and args.year and args.month and args.day:
        args.date = f"{args.year}-{args.month:02d}-{args.day:02d}"

    result = {
        'meeting_title': args.title,
        'meeting_type': 'unknown',
        'company': None,
        'participant': None,
        'confidence': 0,
        'source': 'unknown'
    }

    # Step 1: Try calendar matching (most accurate)
    calendar_event = None
    if args.date:
        calendar_event = match_with_calendar(args.title, args.date, args.time)
        if calendar_event:
            # Use calendar title for classification
            classification = classify_from_calendar_title(calendar_event['title'])
            result.update(classification)
            result['meeting_title'] = calendar_event['title']  # Use calendar title
            result['source'] = 'calendar'
            log(f"Using calendar classification: {result['meeting_type']}", "INFO")

    # Step 2: If no calendar match, try pattern matching on title
    if not calendar_event:
        # First try as if it's a calendar title (might be from meeting-prep.sh)
        classification = classify_from_calendar_title(args.title)
        if classification['confidence'] > 0.7:
            result.update(classification)
            result['source'] = 'title_pattern'
            log(f"Using title pattern classification: {result['meeting_type']}", "INFO")
        else:
            # Fall back to Krisp title classification
            classification = classify_from_krisp_title(args.title)
            result.update(classification)
            result['source'] = 'krisp_pattern'
            log(f"Using Krisp pattern classification: {result['meeting_type']}", "INFO")

    # Step 3: Apply email mapping if we have participants
    if args.participants:
        email_map = load_email_name_map()
        emails = [e.strip().lower() for e in args.participants.split(',')]

        for email in emails:
            if email in email_map:
                name = email_map[email]
                if name != "SKIP":
                    result['participant'] = name
                    break

    # Step 4: Determine company from participant if needed
    if result['participant'] and not result['company']:
        participant_lower = result['participant'].lower()
        if participant_lower in PARTICIPANT_COMPANY_MAP:
            result['company'] = PARTICIPANT_COMPANY_MAP[participant_lower]
        elif result['meeting_type'] == 'one-on-one':
            # Default to IPMedia for internal 1:1s
            result['company'] = 'IPMedia'

    # Step 5: Call find-person-folder if we have a participant
    if result['participant'] and result['company']:
        try:
            script_dir = Path(__file__).parent
            folder_result = subprocess.run(
                ['bash', str(script_dir / 'find-person-folder.sh'), result['participant']],
                capture_output=True,
                text=True,
                timeout=5
            )
            if folder_result.returncode == 0:
                result['person_folder'] = folder_result.stdout.strip()
                log(f"Found person folder: {result['person_folder']}", "INFO")
        except Exception as e:
            log(f"Failed to find person folder: {e}", "WARN")

    # Output JSON result
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())