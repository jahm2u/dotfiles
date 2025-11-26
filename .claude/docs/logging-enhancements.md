# Krisp Automation - Enhanced Logging & Error Handling

**Date:** 2025-11-14
**Status:** In Progress - Phase 1 Complete

---

## 🎯 GOAL

Make errors and logging more explicit for easier debugging:
1. **Better error messages** with full context
2. **Stack traces** for exceptions
3. **Contextual logging** (meeting_id, file paths, etc.)
4. **DEBUG level logging** for detailed troubleshooting
5. **Structured logging** for easier parsing

---

## ✅ PHASE 1 & 2: COMPLETED

### Enhanced Log Function

**Location**: `config/sketchybar/helpers/krisp-process-transcript.py:49-80`

**New Signature**:
```python
def log(message, level="INFO", exc_info=None, context=None):
    """
    Enhanced logging with context and exception support

    Args:
        message: Log message
        level: Log level (DEBUG, INFO, WARN, ERROR)
        exc_info: Exception object for traceback logging
        context: Dict of contextual information (meeting_id, file_path, etc.)
    """
```

**Features**:
1. **Context Support**: Attach metadata to log messages
   ```python
   log("Processing failed", "ERROR", context={"meeting_id": "123", "stage": "classification"})
   ```
   Output: `[2025-11-14 12:00:00] [ERROR] [meeting_id=123, stage=classification] Processing failed`

2. **Exception Tracebacks**: Full stack traces in log file
   ```python
   try:
       risky_operation()
   except Exception as e:
       log("Operation failed", "ERROR", exc_info=e, context=ctx)
   ```
   Output includes full traceback in log file

3. **DEBUG Level**: Verbose logging for troubleshooting
   ```python
   log("Found 5 speaker lines in transcript", "DEBUG", context=ctx)
   ```

4. **Structured Output**: Console shows summary, file has full details

### Enhanced Functions

#### 1. extract_speakers()

**Lines**: 83-127

**Improvements**:
- Added context dict with function name and transcript path
- DEBUG logs for file size and speaker count
- Specific exceptions (FileNotFoundError vs generic Exception)
- Full tracebacks on errors
- Logs input/output for debugging

**Example Output**:
```
[2025-11-14 12:00:00] [DEBUG] [function=extract_speakers, transcript=/path/to/file.txt] Reading transcript file
[2025-11-14 12:00:00] [DEBUG] [function=extract_speakers, transcript=/path/to/file.txt] Transcript size: 14523 bytes
[2025-11-14 12:00:00] [DEBUG] [function=extract_speakers, transcript=/path/to/file.txt] Found 42 speaker lines in transcript
[2025-11-14 12:00:00] [DEBUG] [function=extract_speakers, transcript=/path/to/file.txt] Extracted 3 unique speakers: ['Pedro', 'Marcus', 'Ana']
```

#### 2. search_calendar_by_participant()

**Lines**: 130-193

**Improvements**:
- Context includes participant name and date
- Logs khal command being executed
- DEBUG logs for khal output parsing
- Specific exceptions (TimeoutExpired, FileNotFoundError)
- Logs exit codes and stderr on failures
- Tracks found events count

**Example Output**:
```
[2025-11-14 12:00:01] [DEBUG] [function=search_calendar_by_participant, participant=Marcus, date=2025-11-10] Searching calendar for participant 'Marcus' on 2025-11-10
[2025-11-14 12:00:01] [DEBUG] [function=search_calendar_by_participant, participant=Marcus, date=2025-11-10] Running command: khal list --day-format  2025-11-10 1d
[2025-11-14 12:00:02] [DEBUG] [function=search_calendar_by_participant, participant=Marcus, date=2025-11-10] Got 8 lines from khal
[2025-11-14 12:00:02] [DEBUG] [function=search_calendar_by_participant, participant=Marcus, date=2025-11-10] Found matching event line: 10:00-11:00 Weekly Sync with Marcus
[2025-11-14 12:00:02] [DEBUG] [function=search_calendar_by_participant, participant=Marcus, date=2025-11-10] Found 1 matching calendar events
```

#### 3. process_transcript()

**Lines**: 205-276 (enhanced beginning, more to come)

**Improvements**:
- Context dict created at start with meeting_id and transcript path
- All subsequent logs include this context automatically
- Stage numbers in log messages
- File paths logged for pending downloads
- DEBUG logs for file operations

**Example Output**:
```
[2025-11-14 12:00:00] [INFO] [meeting_id=019a6df..., transcript=/path/to/file.txt] Starting transcript processing pipeline
[2025-11-14 12:00:00] [INFO] [meeting_id=019a6df..., transcript=/path/to/file.txt] Stage 1: Loading meeting metadata
[2025-11-14 12:00:00] [DEBUG] [meeting_id=019a6df..., transcript=/path/to/file.txt] Reading pending downloads from /Users/v/.cache/sketchybar/krisp-pending-downloads.json
```

---

## 📊 LOG LEVELS

**DEBUG**: Verbose debugging information
- Function entry/exit
- Variable values
- File sizes
- Command output
- Intermediate results

**INFO**: Normal operational messages
- Stage completion
- Successful operations
- Status updates

**WARN**: Degraded but non-critical issues
- Missing optional data
- Retryable failures
- Fallback behaviors

**ERROR**: Critical failures
- Exceptions with stack traces
- Missing required data
- Unrecoverable errors

---

## 🔧 USAGE

### For Developers

**Enable DEBUG logging** by setting environment variable:
```bash
export KRISP_LOG_LEVEL=DEBUG
```

**View enhanced logs**:
```bash
# Tail logs with context
tail -f ~/.config/sketchybar/logs/krisp-automation.log | grep "meeting_id=019a"

# Search for errors with full tracebacks
grep -A 20 "ERROR" ~/.config/sketchybar/logs/krisp-automation.log

# Find specific function logs
grep "function=extract_speakers" ~/.config/sketchybar/logs/krisp-automation.log
```

### For Users

**Check last error**:
```bash
tail -100 ~/.config/sketchybar/logs/krisp-automation.log | grep -A 10 "ERROR"
```

**Track specific meeting**:
```bash
grep "meeting_id=019a6df" ~/.config/sketchybar/logs/krisp-automation.log
```

#### 4. process_transcript() - Calendar Matching & Classification

**Lines**: 276-380

**Improvements**:
- Context updated with meeting title, date, time
- Classification command logged with full arguments
- JSON parse errors caught separately with output samples
- Timeout errors tracked (180s limit)
- Classification results logged (type, confidence)
- Speaker-based matching logged with decision rationale
- Match confidence comparisons shown

**Example Output**:
```
[2025-11-14 12:00:00] [INFO] [meeting_id=019a6df, transcript=/path/file.txt, title=Weekly Sync, date=2025-11-10, time=10:00 AM] Found metadata: Weekly Sync
[2025-11-14 12:00:00] [DEBUG] [meeting_id=019a6df, title=Weekly Sync, date=2025-11-10] Meeting date: 2025-11-10, time: 10:00 AM
[2025-11-14 12:00:00] [INFO] [meeting_id=019a6df, title=Weekly Sync] Stage 1: Matching to calendar event...
[2025-11-14 12:00:00] [DEBUG] [meeting_id=019a6df] Running classification: --title Weekly Sync --date 2025-11-10 --time 10:00 AM
[2025-11-14 12:00:02] [DEBUG] [meeting_id=019a6df] Classification output: 523 bytes
[2025-11-14 12:00:02] [INFO] [meeting_id=019a6df] Classification result: type=ipmedia_team_hr, confidence=0.85
[2025-11-14 12:00:02] [INFO] [meeting_id=019a6df] Stage 2: Speaker-based matching (fallback/validation)
[2025-11-14 12:00:02] [INFO] [meeting_id=019a6df, speakers=['Pedro', 'Ana']] Extracted 2 speakers from transcript: ['Pedro', 'Ana']
[2025-11-14 12:00:02] [DEBUG] [meeting_id=019a6df, speakers=['Pedro', 'Ana']] Attempting speaker-based calendar matching with primary speaker: Pedro
[2025-11-14 12:00:03] [INFO] [meeting_id=019a6df, speakers=['Pedro', 'Ana']] Speaker-based match found 1 calendar events for 'Pedro'
```

---

## 📦 PHASE 2 COMPLETED

### Files Enhanced

### Remaining Functions to Enhance

1. **Classification** (`classify-meeting-unified.py`)
   - Add context to all classification attempts
   - Log pattern matches and confidence scores
   - Trace calendar event matching logic

2. **Calendar Matching** (rest of `process_transcript()`)
   - Log calendar search attempts
   - Track time window adjustments
   - Log speaker-based fallback logic

3. **Person Folder Search**
   - Log search paths tried
   - Show why folders were rejected
   - Trace vault structure navigation

4. **AI Analysis** (`krisp-update-note.py`)
   - Log OpenAI API calls
   - Track token usage
   - Show prompts and responses (truncated)

5. **Note Update** (`krisp-update-note.py`)
   - Log file operations
   - Show section matching logic
   - Track content changes

6. **Transcript Organization**
   - Log file moves and renames
   - Show path calculations
   - Track attachment folder creation

7. **Batch Processing** (`krisp-batch-process.py`)
   - Add per-meeting context
   - Track queue progress
   - Log success/failure reasons

8. **Download Script** (`krisp-download-transcripts-simple.py`)
   - Add Playwright operation logging
   - Track page navigation
   - Log clipboard operations

---

## 📝 EXAMPLE: Before vs After

### BEFORE
```
[2025-11-14 12:00:00] [WARN] Error searching calendar by participant: expected str, bytes or os.PathLike object, not NoneType
```

**Problems**:
- No meeting ID (which meeting failed?)
- No context (what participant? what date?)
- No stack trace (where did it fail?)
- Generic error message

### AFTER
```
[2025-11-14 12:00:00] [ERROR] [function=search_calendar_by_participant, participant=Marcus, date=2025-11-10, meeting_id=019a6df] Calendar search failed unexpectedly
[2025-11-14 12:00:00] [ERROR] Exception: TypeError: expected str, bytes or os.PathLike object, not NoneType
[2025-11-14 12:00:00] [ERROR] Traceback (most recent call last):
[2025-11-14 12:00:00] [ERROR]   File "krisp-process-transcript.py", line 271, in process_transcript
[2025-11-14 12:00:00] [ERROR]     participant_events = search_calendar_by_participant(speakers[0], event_date)
[2025-11-14 12:00:00] [ERROR]   File "krisp-process-transcript.py", line 151, in search_calendar_by_participant
[2025-11-14 12:00:00] [ERROR]     result = subprocess.run(khal_cmd, ...)
[2025-11-14 12:00:00] [ERROR] TypeError: expected str, bytes or os.PathLike object, not NoneType
```

**Improvements**:
- Meeting ID identifies which meeting
- Context shows function, participant, date
- Full stack trace shows exact line
- Clear exception type and message

---

## 🎯 BENEFITS

1. **Faster Debugging**: Context helps identify issues quickly
2. **Better Support**: Users can provide full error context
3. **Proactive Monitoring**: Pattern detection in logs
4. **Performance Analysis**: DEBUG logs show bottlenecks
5. **Audit Trail**: Full history of operations

---

## 📦 FILES MODIFIED

### Phase 1 (Completed)
- `config/sketchybar/helpers/krisp-process-transcript.py`:
  - Lines 49-80: Enhanced `log()` function
  - Lines 83-127: Enhanced `extract_speakers()`
  - Lines 130-193: Enhanced `search_calendar_by_participant()`
  - Lines 205-276: Enhanced `process_transcript()` (beginning)

### Phase 2 (Planned)
- `config/sketchybar/helpers/classify-meeting-unified.py`
- `config/sketchybar/helpers/krisp-update-note.py`
- `config/sketchybar/helpers/krisp-batch-process.py`
- `config/sketchybar/helpers/krisp-download-transcripts-simple.py`

---

## ✅ TESTING

**Syntax Check**: ✅ Passed
```bash
cd ~/.config/sketchybar/helpers
~/.config/sketchybar/venv/bin/python3 -m py_compile krisp-process-transcript.py
```

**Next Steps**:
1. Process a test meeting to verify enhanced logging works
2. Check log file for proper formatting
3. Verify stack traces appear on errors
4. Continue Phase 2 enhancements

---

**Status**: Phase 1 complete, ready for testing and Phase 2
