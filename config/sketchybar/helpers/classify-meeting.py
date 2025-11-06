#!/usr/bin/env python3
"""
Meeting Classification Script
Classifies calendar meetings by type, extracts participants, and determines company context.
"""

import argparse
import json
import re
import sys
import os


def load_email_name_map():
    """Load email to Obsidian name mapping from config file."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    map_file = os.path.join(script_dir, "email-name-map.txt")

    email_map = {}
    if os.path.exists(map_file):
        with open(map_file, 'r') as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if not line or line.startswith('#'):
                    continue
                if '=' in line:
                    email, name = line.split('=', 1)
                    email_map[email.strip().lower()] = name.strip()

    return email_map


def extract_participant_from_emails(emails: str, email_map: dict) -> str:
    """Extract participant name from comma-separated email list using mapping."""
    if not emails:
        return "unknown"

    # Split by comma and clean
    email_list = [e.strip().lower() for e in emails.split(',')]

    # Look for first non-SKIP email in map
    for email in email_list:
        if email in email_map:
            name = email_map[email]
            if name != "SKIP":
                return name

    # If no mapping found, try to extract from email (before @)
    for email in email_list:
        if '@' in email:
            local_part = email.split('@')[0]
            # Skip if it looks like Jeff
            if 'jeff' in local_part.lower():
                continue
            # Extract name part (e.g., eric.kiqumoto -> Eric)
            name_part = local_part.split('.')[0]
            if name_part:
                return name_part.capitalize()

    return "unknown"


def classify_meeting(title: str, date: str, participants: str) -> dict:
    """
    Classify a meeting based on its title, date, and participants.

    Args:
        title: Meeting title/subject
        date: Meeting date (YYYY-MM-DD format)
        participants: Comma-separated list of participants

    Returns:
        dict: Classification result with meeting_type, company, participant, confidence
    """
    title_lower = title.lower()

    # Default result
    result = {
        "meeting_type": "unknown",
        "company": "unknown",
        "participant": "unknown",
        "confidence": 0
    }

    # Load email mapping
    email_map = load_email_name_map()

    # Extract participant from attendee emails (if provided)
    if participants:
        result["participant"] = extract_participant_from_emails(participants, email_map)

    # Executive meeting with Ron (special case - highest priority)
    if re.search(r'\bjeff\s*/\s*ron\b', title_lower) or re.search(r'\bron\s*/\s*jeff\b', title_lower):
        result["meeting_type"] = "ipmedia_executive"
        result["company"] = "IPMedia"
        result["participant"] = "Ron"
        result["confidence"] = 95
        return result

    # 1-on-1 patterns (including "Vlad & Jeff" format)
    oneon1_patterns = [
        r'\b1\s*on\s*1\b',
        r'\b1-on-1\b',
        r'\b1:1\b',
        r'\bone\s*on\s*one\b',
        r'\bvlad\s+(and|&)\s+jeff\b',  # "Vlad & Jeff moving forward"
        r'\bjeff\s+(and|&)\s+vlad\b'
    ]
    for pattern in oneon1_patterns:
        if re.search(pattern, title_lower):
            # Extract participant from title if not already found from emails
            if result["participant"] == "unknown":
                title_words = title.split()
                for word in title_words:
                    # Skip common meeting keywords
                    if word.lower() in ['1on1', '1-on-1', '1:1', 'with', 'and', '&', 'jeff', 'hamersly', 'meeting', 'sync', 'weekly', 'standup', 'moving', 'forward', 'on', 'projects']:
                        continue
                    # Found a potential name - take it
                    if len(word) > 1 and word[0].isupper():
                        result["participant"] = word
                        break

            result["meeting_type"] = "ipmedia_1on1"
            result["company"] = "IPMedia"
            result["confidence"] = 90
            return result

    # Company meeting patterns
    company_patterns = {
        "TP": [r'\btp\s+weekly\b', r'\bweekly\s+.*\s+tp\b', r'\bweekly\s+meeting\s+tp\b', r'\btraffic\s+partners?\b'],
        "MT": [r'\bmt\s+weekly\b', r'\bmasstraffic\s+weekly\b', r'\bmass\s*traffic\b'],
        "EX": [r'\bex\s+weekly\b', r'\bexcelsior\b', r'\bweekly\s+meeting\s+excelsior\b'],
        "DT": [r'\bdt\s+weekly\b', r'\bdata\s*tech\b', r'\bjeff\s+and\s+dboy\b', r'\bdboy\b'],
        "PD": [r'\bpd\s+weekly\b', r'\bpd\s+-\s+', r'\bproduct\s+dev\b']
    }

    for company, patterns in company_patterns.items():
        for pattern in patterns:
            if re.search(pattern, title_lower):
                result["meeting_type"] = f"co_{company.lower()}_meeting"
                result["company"] = company
                result["confidence"] = 88
                return result

    # Company-wide meeting patterns (check BEFORE team patterns for compound cases)
    # Example: "Reunião de KPI - Aberta" should be company-wide, not BI team
    company_wide_patterns = [
        r'\bheadquarters\s+meeting\b',
        r'\binternal\s+meeting\b',
        r'\boverview\b',
        r'\ball[\s-]?hands\b',
        r'\baberta\b'  # "Aberta" = Open/company-wide in Portuguese
    ]

    for pattern in company_wide_patterns:
        if re.search(pattern, title_lower):
            result["meeting_type"] = "ipmedia_company_wide"
            result["company"] = "IPMedia"
            result["confidence"] = 85
            return result

    # Team meeting patterns (check before fallback 1-on-1 rule)
    team_patterns = {
        "bi": [
            r'\bbi\s+team\b',
            r'\bbi\s+dashboard\b',
            r'\bbi\s+meeting\b',
            r'\bbusiness\s+intelligence\b',
            r'\bkpi\b',  # KPI meetings typically BI team
            r'\bweekly\s+kpi\b'
        ],
        "traffic": [
            r'\btraffic\s+team\b'
        ],
        "development": [
            r'\bdev\s+team\b',
            r'\bdevelopment\s+team\b',
            r'\bdev\s+coworking\b',
            r'\binterage\b',  # Interage = dev coworking
            r'\bjade\b',  # Squad names
            r'\bkitana\b',
            r'\bmileena\b',
            r'\bskarlet\b',
            r'\bclc\b'
        ],
        "operations": [
            r'\bops\s+team\b',
            r'\boperations\s+team\b',
            r'\boperations\s+weekly\b'
        ],
        "marketing": [
            r'\bmarketing\s+team\b',
            r'\bmarketing\s+meeting\b',
            r'\bmarketing\s+sync\b',
            r'\bmkt\s+headquarter\b',
            r'\bsocial\s+media\b',
            r'\bpress\b.*\bheadquarter'
        ],
        "leadership": [
            r'\bleadership\s+team\b',
            r'\bleadership\s+meeting\b',
            r'\bexecutive\s+team\b'
        ],
        "hr": [
            r'\bhr\s+team\b',
            r'\bhr\s+.*\s+weekly\b',
            r'\brecruitment\s+weekly\b',
            r'\brh\s+.*\s+suporte\b'  # RH = HR in Portuguese
        ],
        "product": [
            r'\bproduct\s+team\s+meeting\b',
            r'\bproduct\s+discussion\b'
        ],
        "gone": [
            r'\bgone\s+-?\s+weekly\s+sync\b',
            r'\bgone\s+weekly\b',
            r'\bgone\s+sync\b'
        ],
        "slackbot": [
            r'\bslackbot\s+weekly\b',
            r'\bslackbot\s+team\b'
        ],
        "seo": [
            r'\bseo\b',
            r'\[\s*seo\s*\]'
        ]
    }

    for team, patterns in team_patterns.items():
        for pattern in patterns:
            if re.search(pattern, title_lower):
                result["meeting_type"] = f"ipmedia_team_{team}"
                result["company"] = "IPMedia"
                result["confidence"] = 85
                return result

    # Standup patterns
    if re.search(r'\bstandup\b', title_lower):
        result["meeting_type"] = "ipmedia_standup"
        result["company"] = "IPMedia"
        result["confidence"] = 85
        return result

    # If we have a participant but no pattern match, assume 1-on-1
    if result["participant"] != "unknown":
        result["meeting_type"] = "ipmedia_1on1"
        result["company"] = "IPMedia"
        result["confidence"] = 75
        return result

    # Unknown meeting type
    result["confidence"] = 50
    return result


def main():
    parser = argparse.ArgumentParser(description="Classify calendar meeting")
    parser.add_argument("--title", required=True, help="Meeting title")
    parser.add_argument("--date", required=True, help="Meeting date (YYYY-MM-DD)")
    parser.add_argument("--participants", default="", help="Comma-separated participants")

    args = parser.parse_args()

    try:
        result = classify_meeting(args.title, args.date, args.participants)
        print(json.dumps(result, indent=2))
        sys.exit(0)
    except Exception as e:
        error_result = {
            "error": str(e),
            "meeting_type": "unknown",
            "company": "unknown",
            "participant": "unknown",
            "confidence": 0
        }
        print(json.dumps(error_result, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
