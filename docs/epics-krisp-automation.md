# dotfiles - Epic 4.2: Krisp Transcript Automation

## Epic Overview

**Epic:** Krisp Transcript Automation

**Goal:** Eliminate manual transcript processing by automatically downloading Krisp meeting transcripts, matching them to calendar events, analyzing with AI, and updating Obsidian meeting notes with structured post-meeting summaries.

**Scope:**
- Automated browser-based transcript downloads from Krisp.ai using Playwright
- Calendar matching with ±15-minute tolerance to link transcripts to meetings
- AI-powered transcript analysis generating discussion highlights, action items, and follow-up topics
- Automatic Obsidian note updates with Post-Meeting Summary sections
- Hourly automation via LaunchAgent with comprehensive error handling
- Telegram alerting for authentication failures and processing status

**Out of Scope:**
- Real-time transcript capture during meetings
- Multi-platform transcript sources (Otter.ai, Fireflies.ai, etc.)
- Local LLM integration (OpenAI only for MVP)
- Automatic cookie refresh (manual export required)
- Meeting insights dashboard and analytics

**Success Criteria:**
- Hourly automation runs reliably without manual intervention
- 95%+ calendar matching accuracy with ±15-minute window
- AI-generated summaries are actionable and accurate
- Zero duplicate processing (idempotent cache system)
- Auth failures trigger Telegram alerts within 60 seconds
- Cost remains under $0.50/day (~50 meetings)
- Processing completes within 3 minutes for 5-meeting batches

---

## Epic Details

### User Value

**Problem:** After meetings, you manually download transcripts from Krisp, read through them, extract action items, and update meeting notes. This takes 10-15 minutes per meeting and is easy to forget.

**Solution:** Automated pipeline that hourly checks Krisp for new transcripts, downloads them, analyzes with AI, and updates your Obsidian notes with structured summaries including action items and discussion highlights.

**Benefit:** Saves 50-75 minutes/week on transcript processing, ensures no action items are missed, and maintains continuity between meetings automatically.

### Dependencies

**Internal Dependencies:**
- Epic 4.1 (Obsidian Meeting Prep Integration) - Uses person folder discovery and note structure
- Epic 2 (Calendar Automation) - Requires khal database for calendar matching
- Epic 1 (Environment Configuration) - Requires .env pattern

**External Dependencies:**
- Playwright 1.40.0 with Chromium browser
- OpenAI API access with GPT-4o-mini model
- Telegram Bot API for alerting
- Krisp.ai account with meeting transcripts
- Obsidian vault with established person folder structure

### Technical Complexity

**High Complexity Areas:**
- Anti-detection browser automation (Playwright stealth)
- DOM scraping on potentially changing Krisp interface
- Calendar matching algorithm with ambiguous meetings
- AI prompt engineering for accurate summary generation

**Medium Complexity Areas:**
- Idempotent processing with cache management
- Error handling across multiple failure modes
- LaunchAgent configuration and PATH issues

**Low Complexity Areas:**
- Telegram alerting (simple API call)
- Transcript file storage (standard filesystem operations)
- Obsidian note updates (string manipulation)

---

## Story Breakdown

### Story Map

```
Epic 4.2: Krisp Transcript Automation
├── Story 1: Browser Automation & Transcript Download (5 points)
├── Story 2: AI Analysis & Note Integration (3 points)
└── Story 3: Production Deployment & Monitoring (3 points)
```

**Total Story Points:** 11
**Estimated Timeline:** 1.5 sprints (11 days at 1 point/day)

---

## Implementation Sequence

### Story 1: Browser Automation & Transcript Download

**Prerequisites:** None (foundational story)

**Delivers:**
- Playwright stealth configuration
- Cookie-based authentication
- Krisp meeting list scraping
- Transcript download automation
- Filename parsing and metadata extraction
- Processed meetings cache system

**Validation:**
- Successfully authenticates with Krisp using cookies
- Downloads transcripts for unprocessed meetings
- Parses filenames to extract date/time/source
- Stores transcripts in temp directory
- Updates cache to prevent duplicates

**Blocks:** Stories 2 & 3 (they depend on transcript download working)

---

### Story 2: AI Analysis & Note Integration

**Prerequisites:** Story 1 (requires downloaded transcripts)

**Delivers:**
- Calendar matching algorithm (±15-minute window)
- Meeting type classification (reuse from Story 4-1)
- Person folder discovery (reuse from Story 4-1)
- GPT-4o-mini transcript analysis
- Post-Meeting Summary generation
- Obsidian note updates
- Transcript file organization in person/attachments/

**Validation:**
- Matches transcripts to calendar events with 95%+ accuracy
- AI generates actionable summaries with discussion highlights
- Obsidian notes updated with structured Post-Meeting Summary
- Transcripts saved to correct person folders
- Failed matches logged in cache for manual review

**Blocks:** Story 3 (orchestration depends on analysis working)

---

### Story 3: Production Deployment & Monitoring

**Prerequisites:** Stories 1 & 2 (requires full pipeline working)

**Delivers:**
- Orchestration bash script (krisp-orchestrator.sh)
- LaunchAgent configuration (hourly execution)
- Comprehensive logging system
- Telegram error alerting
- Retry logic with exponential backoff
- Integration with meeting-prep.sh (Story 4-1)
- End-to-end testing and validation

**Validation:**
- LaunchAgent runs every hour automatically
- Full workflow completes successfully for 5-meeting batch
- Errors logged with detailed context
- Telegram alerts sent on auth failures
- Meeting prep workflow triggers after transcript processing
- No crashes or data loss on errors

**Blocks:** None (final story in epic)

---

## Story Summaries

### Story 1: Browser Automation & Transcript Download (5 points)

**As a** macOS user with Krisp meeting transcripts,
**I want** automated browser-based transcript downloads from Krisp.ai,
**so that** I don't have to manually export transcripts after every meeting.

**Key Deliverables:**
- Playwright stealth browser automation
- Cookie-based Krisp authentication
- Meeting list web scraping
- Transcript download automation
- Filename parsing and metadata extraction
- Idempotent processing cache

**Estimated Effort:** 5 story points (5 days)

---

### Story 2: AI Analysis & Note Integration (3 points)

**As a** macOS user with downloaded meeting transcripts,
**I want** AI-powered analysis that updates my Obsidian notes with structured summaries,
**so that** I have actionable post-meeting insights without manual review.

**Key Deliverables:**
- Calendar matching with ±15-minute tolerance
- GPT-4o-mini transcript analysis
- Post-Meeting Summary generation (highlights, action items, follow-ups)
- Obsidian note automatic updates
- Transcript organization in person folders

**Estimated Effort:** 3 story points (3 days)

---

### Story 3: Production Deployment & Monitoring (3 points)

**As a** macOS user with automated transcript processing,
**I want** reliable hourly execution with comprehensive error handling and alerting,
**so that** the automation runs unattended and I'm notified of any issues.

**Key Deliverables:**
- Orchestration script (krisp-orchestrator.sh)
- LaunchAgent hourly scheduling
- Comprehensive logging
- Telegram error alerting
- Retry logic and graceful degradation
- Integration with Story 4-1 meeting prep

**Estimated Effort:** 3 story points (3 days)

---

## Testing Strategy

### Unit Testing
- Cookie loading and validation
- Filename parsing (multiple formats)
- Calendar matching algorithm (various time windows)
- AI prompt generation

### Integration Testing
- End-to-end workflow (auth → download → analyze → update)
- Error scenarios (auth failures, missing person, AI errors)
- Idempotent processing (re-run safety)

### Acceptance Testing
- Process 5 real transcripts successfully
- Verify Obsidian notes updated correctly
- Confirm Telegram alerts on failures
- Validate LaunchAgent reliability over 1 week

---

## Risk Assessment

### High Risks

**Risk:** Krisp DOM structure changes break scraping
- **Mitigation:** Defensive selectors, fallback strategies, quick DOM update process
- **Probability:** Medium (every 3-6 months)
- **Impact:** High (blocks all downloads)

**Risk:** OpenAI API rate limits or cost overruns
- **Mitigation:** Daily budget cap ($0.50), batch size limit (5 meetings/hour)
- **Probability:** Low
- **Impact:** Medium (delayed processing)

### Medium Risks

**Risk:** Calendar matching ambiguity (multiple meetings in window)
- **Mitigation:** Source name disambiguation, manual review queue
- **Probability:** Medium (10-20% of meetings)
- **Impact:** Medium (requires manual intervention)

**Risk:** Cookie expiration causing auth failures
- **Mitigation:** Telegram alerts, clear manual refresh instructions
- **Probability:** High (every 30 days)
- **Impact:** Low (quick manual fix)

### Low Risks

**Risk:** LaunchAgent PATH issues
- **Mitigation:** Explicit PATH in plist, documented in tech-spec
- **Probability:** Low (one-time setup)
- **Impact:** Low (easy fix)

---

## Cost Analysis

**Development Cost:**
- Story 1: 5 story points × 1 day/point = 5 days
- Story 2: 3 story points × 1 day/point = 3 days
- Story 3: 3 story points × 1 day/point = 3 days
- **Total:** 11 days (1.5 sprints)

**Operational Cost (monthly):**
- OpenAI API: 10 meetings/day × 30 days × $0.01 = **$3.00/month**
- Telegram API: Free
- Playwright: Free
- **Total:** $3.00/month

**ROI Calculation:**
- Time saved: 10 min/meeting × 10 meetings/day × 30 days = 3,000 min/month (50 hours)
- Value: 50 hours × $100/hour = $5,000/month
- Cost: $3/month
- **ROI:** 166,567% (practically infinite return)

---

## Future Enhancements

1. **Multi-source transcript aggregation** - Otter.ai, Fireflies.ai, Zoom
2. **Real-time transcript capture** - WebSocket integration during live meetings
3. **Local LLM option** - Privacy-focused alternative using Ollama
4. **Speaker diarization** - Better action item attribution with speaker names
5. **Meeting insights dashboard** - Aggregate metrics over time
6. **Auto-cookie refresh** - Playwright session persistence
7. **Slack integration** - Post summaries to relevant channels
8. **Action item tracking** - Cross-meeting completion monitoring

---

**Created:** 2025-11-02
**Epic Status:** Ready for Story 1 Implementation
**Next Action:** Generate context for story-krisp-automation-1.md (SM agent)
