# Problem Solving Session: Install Script Refactoring

**Date:** 2025-11-03
**Problem Solver:** Jeff
**Problem Category:** Software Architecture / UX

---

## 🎯 PROBLEM DEFINITION

### Initial Problem Statement

The install script (scripts/install.sh) is "whacky" - it needs improvement.

### Refined Problem Statement

The dotfiles installation script has three primary issues:
1. **Convoluted structure** - The 1136-line script is complex and hard to follow
2. **Information overload** - Outputs excessive details the user doesn't need to see
3. **Scattered interaction model** - Questions are asked throughout execution, interrupting flow and causing confusion

**Desired state:** Gather ALL questions upfront, ask them in a clear batch, then execute based on answers with clean progress indication and minimal interruption.

### Problem Context

- Script location: `/Users/v/repos/02_personal/dotfiles/scripts/install.sh`
- Size: 1136 lines of bash
- Purpose: Creates symlinks for macOS dotfiles, installs dependencies, configures LaunchAgents
- Features: Preflight checks, Homebrew bundle, calendar sync, Krisp automation, environment setup
- Growth pattern: Started simple, features added organically over time
- Current state: Works functionally but poor user experience

### Success Criteria

1. **Clear upfront questions** - All user input gathered at the beginning in a logical sequence
2. **Clean execution flow** - After questions answered, script runs with minimal interruption
3. **Appropriate verbosity** - Show progress and results, hide implementation details
4. **Maintainable structure** - Modular, easy to understand, easy to extend
5. **Professional UX** - Feels polished, not overwhelming or confusing

---

## 🔍 DIAGNOSIS AND ROOT CAUSE ANALYSIS

### Problem Boundaries (Is/Is Not)

**Where DOES the problem occur?**
- Throughout entire script execution (1136 lines)
- Interactive prompts scattered at 11+ different points
- Verbose preflight checks (lines 43-216)
- Detailed validation output (lines 291-483)

**Where DOESN'T it occur?**
- Core symlink creation logic (clean, works well)
- Helper functions (well-structured)
- Technical outcomes (correct functionality)

**When DOES it happen?**
- During first-time installation
- When running updates
- Throughout entire execution flow

**When DOESN'T it?**
- After completion (results are correct)
- In helper functions (isolated logic is fine)

**Who IS affected?**
- Script maintainer (too complex to modify)
- New users (confusing installation experience)
- Update users (interrupted workflow)

**Who ISN'T affected?**
- The system (technical outcomes work correctly)

**What IS the problem?**
- User experience design flaw (too chatty, interrupts flow)
- Architecture anti-pattern (imperative vs declarative)
- Information architecture (poor signal-to-noise ratio)

**What ISN'T the problem?**
- Core functionality (it works!)
- Bash competency (well-written)
- Feature completeness (has everything needed)

**🎯 Pattern:** The problem is architectural/UX-focused, not functional. Script uses imperative execution model (do→ask→do→ask→do) when it should use declarative planning model (gather→plan→execute→report).

### Root Cause Analysis

**Five Whys Drill-Down:**

1. **Why is the script convoluted and chatty?**
   → It asks questions scattered throughout and shows excessive detail

2. **Why does it ask questions throughout execution?**
   → Each function handles its own interaction when it needs input

3. **Why was each function written to handle its own interaction?**
   → Script grew organically - features added without redesigning flow

4. **Why wasn't the flow redesigned as features were added?**
   → No separation between "configuration gathering" and "execution"

5. **Why was there no separation from the start?**
   → Original script was simple (just symlinks); early design pattern (inline prompts) didn't scale when complex features were added

**🎯 ROOT CAUSE:** Lack of architectural separation of concerns between Configuration (what to do), Execution (doing it), and Reporting (what happened). Classic premature implementation pattern.

### Contributing Factors

1. **Organic growth** - Features added incrementally without refactoring
2. **No design principles** - Missing architectural patterns from day one
3. **Success trap** - "It works" prevented refactoring investment
4. **Bash limitations** - Language doesn't enforce structure like OOP languages
5. **Mixed concerns** - Validation, prompting, execution, and reporting all interleaved
6. **Copy-paste expansion** - Similar patterns repeated instead of abstracted
7. **No verbosity control** - Everything at same detail level

### System Dynamics

**Reinforcing Loop (Vicious Cycle):**
- Script grows → Harder to understand → Easier to add than refactor → Script grows more → Complexity increases

**Constraint:**
- All logic in single 1136-line file makes refactoring risky (fear of breaking working system)

**Feedback Delay:**
- Problem isn't apparent during development, only during actual use (delayed pain)

**Leverage Point:**
- Separating concerns breaks the vicious cycle - once structure exists, adding features becomes cleaner

---

## 📊 ANALYSIS

### Force Field Analysis

**Driving Forces (Supporting Solution):**
1. **Pain is real** - Experiencing friction NOW (strong motivator)
2. **High ROI** - Fix once, benefit every future install/update
3. **Code quality standards** - Maintain clean codebase pride
4. **Future maintenance** - Easier to extend after refactor
5. **User experience** - Better for others using dotfiles
6. **Learning opportunity** - Implement clean architecture patterns
7. **Documentation clarity** - Better structure = easier to document

**Restraining Forces (Blocking Solution):**
1. **"If it ain't broke..."** - Current script works functionally
2. **Time investment** - Refactoring takes time from other work
3. **Risk of breakage** - Working system could break during refactor
4. **Testing burden** - Need to validate all paths after changes
5. **Bash constraints** - Language makes patterns awkward
6. **Scope uncertainty** - Not clear how far to refactor
7. **No immediate crisis** - Can continue using current version

### Constraint Identification

**Primary Constraint:**
- Single monolithic file (1136 lines) makes incremental improvement risky

**Real Constraints:**
- Must maintain backward compatibility (.env files, LaunchAgents)
- Bash scripting limitations (no proper data structures/modules)
- macOS-specific dependencies (limited test environments)
- Must be idempotent (safe to run multiple times)

**Assumed Constraints (Challenge These!):**
- ❌ "Must be single file" → Could split into modules
- ❌ "Must ask everything interactively" → Could use smart defaults with override flags
- ❌ "Must show all details" → Could have quiet/verbose modes
- ❌ "Must validate inline" → Could defer to separate phase

### Key Insights

1. **Strongest driving force: PAIN** - Experiencing it now makes this the right time
2. **Strongest restraining force: RISK** - Fear of breaking working system
3. **Leverage point: Phased refactoring** - Don't rewrite everything, restructure incrementally
4. **Smart defaults reduce interaction** - If .env exists, don't ask; if khal installed, assume yes
5. **Verbosity modes solve overload** - Default to clean progress, offer --verbose flag
6. **Separation of concerns is key** - Configuration → Planning → Execution → Reporting phases
7. **Current code is template** - Keep all logic, just reorganize flow

---

## 💡 SOLUTION GENERATION

### Methods Used

1. **TRIZ Contradiction Resolution** - Resolve "simpler AND more powerful" paradox
2. **Morphological Analysis** - Map solution space dimensions systematically
3. **Lateral Thinking** - Challenge assumptions about install script conventions

### Generated Solutions

**🎯 INCREMENTAL APPROACHES (Low Risk, Medium Impact):**

1. **Add --quiet flag** - Keep structure, suppress verbose output
2. **Batch questions at top** - Move all ask_user() calls to preflight phase
3. **Extract .env defaults** - Read existing config before asking questions
4. **Clean progress indicators** - Replace verbose logs with spinner/progress bar
5. **Separate validation script** - Optional ./validate.sh post-install

**🚀 MODERATE REDESIGN (Medium Risk, High Impact):**

6. **Four-phase architecture** - Gather → Plan → Execute → Report separation
7. **Configuration file approach** - Generate install.config.yaml, execute from it
8. **Modular file structure** - Split into lib/ directory with sourced modules
9. **Smart defaults engine** - Detect existing state, only ask what's needed
10. **Template + hydration pattern** - Define "what" separately from "how"

**💥 BREAKTHROUGH APPROACHES (Higher Risk, Highest Impact):**

11. **Makefile declarative** - Define targets, let make handle execution
12. **Interactive TUI** - Single cohesive UI (dialog/whiptail) for all questions
13. **Ansible playbook** - Infrastructure-as-code approach
14. **Two-script pattern** - setup-wizard.sh (interactive) + install.sh (silent)
15. **Nix/Home-Manager** - Full declarative system configuration

### Creative Alternatives

**🎨 WILD CARDS:**

16. **Web-based configurator** - Browser UI, configure, download custom script
17. **Git hooks approach** - Pre-commit hook generates install plan
18. **Diff-based updates** - Only touch what changed since last install
19. **Profile system** - Minimal/standard/full presets with overrides
20. **Idempotent modules** - Each feature self-contained, independently runnable

---

## ⚖️ SOLUTION EVALUATION

### Evaluation Criteria

1. **Addresses root cause** (separation of concerns) - Weight: HIGH
2. **Feasibility** (implementable in bash without major breakage) - Weight: HIGH
3. **Time to implement** (hours not weeks) - Weight: MEDIUM
4. **Maintenance burden** (easier to extend in future) - Weight: HIGH
5. **User experience improvement** (solves stated problems) - Weight: HIGH
6. **Risk** (chance of breaking working system) - Weight: MEDIUM

### Solution Analysis

**Decision Matrix (1-10 scale, weighted):**

| Solution | Root Cause | Feasibility | Time | Maintenance | UX | Risk | Score |
|----------|-----------|-------------|------|-------------|----|----|-------|
| #6: Four-Phase Architecture | 10 | 9 | 7 | 10 | 10 | 8 | **9.1** ⭐ |
| #9: Smart Defaults Engine | 6 | 10 | 9 | 8 | 9 | 10 | **8.5** |
| #14: Two-Script Pattern | 10 | 8 | 6 | 7 | 9 | 7 | **7.8** |
| #4: Clean Progress | 3 | 10 | 9 | 9 | 7 | 10 | **7.4** |

**Analysis:**
- Four-phase architecture scores highest (9.1) - directly solves root cause
- Smart defaults (#9) excellent complement - reduces interaction burden
- Clean progress (#4) easy quick win - improves UX immediately
- Two-script pattern powerful but more work

### Recommended Solution

**HYBRID APPROACH: Four-Phase Architecture + Smart Defaults + Clean Output**

Combine solutions #6, #9, and #4 into unified redesign:

**Phase 1: DETECT & GATHER** (Smart Defaults)
- Scan existing state (.env? khal installed? LaunchAgents loaded?)
- Only ask what's truly unknown
- Batch ALL questions in one upfront section

**Phase 2: PLAN** (Show Intent)
- Generate execution plan based on answers
- Display plan: "I will: symlink configs, install khal, setup LaunchAgent"
- Single approval: "Proceed with this plan? [Y/n]"

**Phase 3: EXECUTE** (Clean Progress)
- Run with progress indicators: `[1/7] Creating symlinks... ✓`
- Suppress verbose output (capture to log file)
- Show only errors/warnings inline

**Phase 4: REPORT** (Summary)
- Final summary: "✓ Installed 5/5 components successfully"
- List any issues needing attention
- Show next steps if configuration required

### Rationale

**Why this solution wins:**

✅ **Solves stated problems** - Upfront questions, clean execution flow
✅ **Addresses root cause** - Proper separation of concerns (detect/plan/execute/report)
✅ **Implementable** - Restructure existing code, not full rewrite
✅ **Low risk** - Same logic blocks, better organization
✅ **Maintainable** - Clear phases make future features easier
✅ **Professional UX** - Feels polished, not chaotic
✅ **Quick wins included** - Progress bars provide immediate visible improvement
✅ **Smart behavior** - Detects state, asks less, feels intelligent

**What makes you confident:**
- Leverages all existing code (just reorganizes)
- Each phase has clear responsibility
- Can implement incrementally (phase by phase)
- Bash can handle this pattern well

---

## 🚀 IMPLEMENTATION PLAN

### Implementation Approach

**Strategy: Incremental Refactoring with Feature Preservation**

- Approach: Phased restructuring within same file, then optional extraction
- Philosophy: Working → Better structure → Same working + cleaner
- Risk mitigation: Git branch, preserve all logic, test after each phase
- Timeline: 2-4 hours of focused work
- Validation: Test on fresh macOS user account or VM

### Action Steps

**PHASE 1: Setup & Preparation (15 min)**

1. Create feature branch: `git checkout -b refactor/install-script-four-phase`
2. Commit current state: `git add scripts/install.sh && git commit -m "Snapshot before refactor"`
3. Create backup: `cp scripts/install.sh scripts/install.sh.backup-$(date +%Y%m%d)`
4. Review current function inventory (what exists, what it does)

**PHASE 2: Extract Detection Logic (30 min)**

5. Create `detect_system_state()` function at top of file
6. Move all detection logic here:
   - Check if brew installed
   - Check if khal/sketchybar/aerospace installed
   - Check if .env exists and what's configured
   - Check if LaunchAgents already loaded
   - Check if symlinks already exist
7. Return associative array or serialized state string
8. Test: Run detection, verify it doesn't change anything

**PHASE 3: Create Batched Question Gathering (45 min)**

9. Create `gather_configuration()` function
10. Takes detection results as input
11. Batch ALL questions in logical groups:
    - Group A: Dependencies (install missing? y/n)
    - Group B: Environment (.env setup? OpenAI key? Obsidian path? Calendar URLs?)
    - Group C: Features (calendar LaunchAgent? Krisp automation?)
12. Store answers in config variables (arrays or serialized format)
13. Test: Run gather, verify questions appear in order, nothing executes

**PHASE 4: Generate Execution Plan (30 min)**

14. Create `generate_plan()` function
15. Takes detection + configuration as input
16. Returns structured plan (array of steps):
    ```
    PLAN=(
      "CREATE_SYMLINKS:7:configs"
      "INSTALL_DEPS:3:khal,sketchybar,aerospace"
      "SETUP_LAUNCHAGENT:2:calendar-sync,krisp"
      "CONFIGURE_ENV:1:.env"
    )
    ```
17. Create `display_plan()` function - pretty-print the plan
18. Add approval prompt: "Proceed? [Y/n]"
19. Test: Generate plan, display it, verify human-readable

**PHASE 5: Clean Execution Engine (60 min)**

20. Create `execute_plan()` function
21. Iterate through plan steps with progress tracking
22. Refactor existing execution functions to be silent:
    - Add `QUIET_MODE=true` flag
    - Redirect verbose output to `~/.config/dotfiles-install.log`
    - Only show: `[1/7] Creating symlinks... ✓` style output
23. Implement progress indicators:
    ```bash
    show_progress() {
      local current=$1 total=$2 message=$3
      printf "[%d/%d] %s... " "$current" "$total" "$message"
    }
    show_result() {
      local status=$1  # 0=success, 1=warning, 2=error
      case $status in
        0) echo "✓" ;;
        1) echo "⚠" ;;
        2) echo "✗" ;;
      esac
    }
    ```
24. Test: Execute with clean output, verify log captures details

**PHASE 6: Summary Report (30 min)**

25. Create `generate_report()` function
26. Track results during execution (success/warning/error counts)
27. Display summary:
    ```
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    Installation Complete
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    ✓ 5 components installed successfully
    ⚠ 1 warning: khal database needs first sync

    Next steps:
    1. Restart Sketchybar: brew services restart sketchybar
    2. Check sync logs: tail -f ~/.config/sketchybar/logs/calendar-sync.log

    Full log: ~/.config/dotfiles-install.log
    ```
28. Test: Verify summary is clear and actionable

**PHASE 7: Wire It All Together (30 min)**

29. Refactor `main()` function to call four phases:
    ```bash
    main() {
      echo "Dotfiles Installation"
      echo ""

      # Phase 1: Detect
      detect_system_state

      # Phase 2: Gather
      gather_configuration

      # Phase 3: Plan
      generate_plan
      display_plan
      ask_approval || exit 0

      # Phase 4: Execute
      execute_plan

      # Phase 5: Report
      generate_report
    }
    ```
30. Verify flow makes sense
31. Remove old scattered prompts from execution functions

**PHASE 8: Testing & Validation (30 min)**

32. Test dry-run mode: `bash -n scripts/install.sh` (syntax check)
33. Test on current system (should be idempotent)
34. Verify all features still work:
    - Symlinks created
    - Dependencies installed
    - LaunchAgents loaded
    - .env configured
35. Compare output quality (before vs after screenshots)
36. Check log file contains details

**PHASE 9: Documentation & Polish (15 min)**

37. Add comments to new functions
38. Update README if it references install behavior
39. Add `--help` flag showing usage
40. Optional: Add `--verbose` flag to restore old behavior
41. Commit: `git commit -am "Refactor: Four-phase architecture with clean UX"`

### Timeline and Milestones

**Session 1 (2 hours):** Phases 1-4 (setup through plan generation)
- Milestone: Can generate execution plan without executing

**Session 2 (2 hours):** Phases 5-9 (execution through completion)
- Milestone: Full refactor complete, tested, documented

**Total: 4 hours** (could compress to 2-3 hours if focused)

### Resource Requirements

**Tools needed:**
- Git (branching, commits)
- Text editor (VS Code, vim, etc.)
- Terminal for testing
- Optional: macOS VM or test user account for clean validation

**Knowledge needed:**
- Bash scripting (have it ✓)
- Current script structure (intimate knowledge ✓)
- Risk tolerance (low-medium ✓)

**No external dependencies** - pure refactoring

### Responsible Parties

- **Jeff** - Implementation, testing, approval
- **AI Assistant (me!)** - Can generate specific code snippets if needed during implementation

---

## 📈 MONITORING AND VALIDATION

### Success Metrics

**Quantitative Metrics:**

1. **Lines of code in main()** - Target: <50 lines (currently ~180)
2. **Number of user prompts** - Target: 5-8 batched questions (currently 11+ scattered)
3. **Time to complete** - Target: <2 min for update run (unchanged from current)
4. **Output verbosity** - Target: <30 lines visible output (currently 150+)

**Qualitative Metrics:**

5. **"Feels professional"** - User experience is polished, not overwhelming
6. **"Easy to modify"** - Adding new feature takes <30 min, clear where it goes
7. **"No surprises"** - Plan shows intent before execution, no unexpected behavior
8. **"Quick to understand"** - New contributor reads code, understands flow in <15 min

**Behavioral Validation:**

9. **Idempotency preserved** - Running twice doesn't break or duplicate
10. **Error handling intact** - Failures still caught and reported clearly
11. **All features work** - Nothing regressed (symlinks, LaunchAgents, env setup)

### Validation Plan

**Validation Tests (run before merge):**

**Test 1: Fresh Install**
- Use clean macOS user account or VM
- Run `./scripts/install.sh`
- Verify: Questions batch upfront, execution clean, summary clear
- Check: All symlinks created, LaunchAgents loaded

**Test 2: Update Scenario**
- On existing installation (your current setup)
- Run `./scripts/install.sh` again
- Verify: Detects existing state, asks fewer questions, updates only what changed
- Check: No duplicate LaunchAgents, existing .env preserved

**Test 3: Partial Configuration**
- Delete `.env` file
- Run `./scripts/install.sh`
- Verify: Asks for missing config, creates .env correctly
- Check: Doesn't re-ask about installed dependencies

**Test 4: Error Handling**
- Simulate failure (make brew unavailable temporarily)
- Run `./scripts/install.sh`
- Verify: Error caught, reported clearly, doesn't crash
- Check: Log file contains diagnostic details

**Test 5: User Experience**
- Fresh eyes test (someone unfamiliar)
- Run installation, observe confusion points
- Measure: Time to complete, number of clarifying questions asked

**Test 6: Verbose Mode**
- Run `./scripts/install.sh --verbose`
- Verify: Shows old detailed output for debugging
- Check: Can diagnose issues with extra details

### Risk Mitigation

**Risk 1: Breaking working installation**
- **Probability:** Medium
- **Impact:** High (system configs broken)
- **Mitigation:**
  - Work in git branch
  - Create backup before testing
  - Test on separate user account first
  - Keep old script at `install.sh.v1` during transition
- **Recovery:** Revert git branch, restore from backup

**Risk 2: Missed edge cases**
- **Probability:** Medium
- **Impact:** Medium (some installs fail)
- **Mitigation:**
  - Thorough testing matrix (fresh/update/partial/error cases)
  - Keep validation logic from old script
  - Add more error checking during refactor
- **Recovery:** Fix discovered issues, add test case

**Risk 3: Bash limitations hit**
- **Probability:** Low
- **Impact:** Medium (can't implement cleanly)
- **Mitigation:**
  - Prototype tricky parts first (state detection, plan generation)
  - Use simple data structures (arrays, delimited strings)
  - Fallback: Keep it simpler if bash can't handle it elegantly
- **Recovery:** Adjust design to fit bash constraints

**Risk 4: Time overrun**
- **Probability:** Medium
- **Impact:** Low (just takes longer)
- **Mitigation:**
  - Follow phased approach, can stop at any phase
  - Each phase adds value independently
  - Phase 5 (clean output) can be simplified if time tight
- **Recovery:** Ship partial improvement, finish later

**Risk 5: User confusion with new flow**
- **Probability:** Low
- **Impact:** Low (just need to explain)
- **Mitigation:**
  - Add `--help` text explaining new behavior
  - Keep `--verbose` for those who want old style
  - Update README with example output
- **Recovery:** Gather feedback, adjust messaging

### Adjustment Triggers

**Trigger 1: If testing reveals frequent breakage**
→ **Action:** Reduce scope, implement only Phases 1-3 (questions batching), defer execution cleanup

**Trigger 2: If bash makes clean implementation impossible**
→ **Action:** Switch to two-script approach (#14) - separate wizard from execution

**Trigger 3: If time exceeds 6 hours**
→ **Action:** Ship what's done as v1, schedule Phase 2 refactor later

**Trigger 4: If user feedback is negative**
→ **Action:** Add `--classic` flag for old behavior, iterate on new flow based on feedback

**Trigger 5: If edge cases keep appearing**
→ **Action:** Add comprehensive test suite, consider CI for validation before merges

**Success Trigger (Ship It!):**
- ✅ All 6 validation tests pass
- ✅ Code is cleaner and easier to read
- ✅ Installation feels professional
- ✅ Documented and committed
→ **Action:** Merge to main, update CHANGELOG, celebrate! 🎉

---

## 📝 LESSONS LEARNED

### Key Learnings

1. **Organic growth needs periodic refactoring** - Scripts that "just work" hide accumulating technical debt until UX suffers

2. **Separation of concerns isn't optional** - Even in bash scripts, architectural patterns matter for maintainability

3. **User experience is feature, not polish** - Clean interaction flow should be designed from start, not bolted on

4. **"Working" ≠ "Good"** - Functional correctness doesn't equal quality; UX and maintainability count

5. **Phased refactoring reduces risk** - Don't rewrite from scratch; restructure incrementally while preserving behavior

6. **Smart defaults beat prompts** - Detect state, assume sensible defaults, only ask what's ambiguous

7. **Information architecture matters** - Signal-to-noise ratio affects whether users trust and use your tools

8. **Bash has limits, work with them** - Simple data structures (arrays, strings) beat fighting language constraints

### What Worked

**Problem-Solving Process:**
- ✅ Five Whys drilled to root cause (architectural separation missing)
- ✅ Is/Is Not Analysis revealed problem was UX/architecture, not functionality
- ✅ Force Field Analysis identified strongest driver (pain) and blocker (risk)
- ✅ Multiple solution generation created options from incremental to breakthrough
- ✅ Decision matrix objectively evaluated trade-offs

**Solution Design:**
- ✅ Hybrid approach combined best of multiple options
- ✅ Four-phase architecture directly addresses root cause
- ✅ Smart defaults reduce interaction burden
- ✅ Clean progress output solves information overload
- ✅ Incremental implementation path minimizes risk

**Execution Strategy:**
- ✅ Git branching protects working system
- ✅ Phased implementation allows pause/resume
- ✅ Comprehensive test plan validates no regression
- ✅ Risk mitigation planned for likely failure modes

### What to Avoid

**In Future Scripts:**
- ❌ Don't mix configuration gathering with execution
- ❌ Don't show implementation details users don't need
- ❌ Don't scatter user interaction throughout script
- ❌ Don't let "it works" prevent refactoring when UX degrades
- ❌ Don't copy-paste similar code instead of abstracting
- ❌ Don't skip verbosity modes (--quiet/--verbose flags)

**In Problem-Solving:**
- ❌ Don't jump to solutions before understanding root cause
- ❌ Don't assume only one solution exists
- ❌ Don't ignore emotional factors (your frustration is data!)
- ❌ Don't let perfect be enemy of good (phased beats all-at-once)
- ❌ Don't skip validation planning (risk mitigation matters)

**In Refactoring:**
- ❌ Don't rewrite from scratch (preserve working logic)
- ❌ Don't change everything at once (incremental safer)
- ❌ Don't skip testing after each phase
- ❌ Don't forget backward compatibility (.env, LaunchAgents)
- ❌ Don't remove old behavior without deprecation path

---

## 🎯 NEXT ACTIONS

**Immediate (if proceeding with implementation):**

1. **Decide:** Commit to implementing this refactor (estimated 2-4 hours)
2. **Schedule:** Block focused time for Session 1 (Phases 1-4)
3. **Prepare:** Review action steps, ensure git workspace clean
4. **Execute:** Follow implementation plan step-by-step
5. **Validate:** Run test suite before merging to main

**Alternative (if not ready now):**

- Save this problem-solution doc for reference
- Keep using current script (it works!)
- Revisit when pain intensifies or have free time
- Consider shipping just Phase 3 (batched questions) as quick win

**Meta-Learning:**

- Apply "Four-Phase Architecture" pattern to other automation scripts
- Remember: UX matters even in developer tools
- Schedule periodic refactoring sessions (quarterly?) for critical scripts
- Document architectural decisions to prevent repeat issues

---

_Problem-solving session completed: 2025-11-03_
_Framework used: BMAD Creative Intelligence Suite - Problem Solving Workflow_
_Total time: Diagnosis (20 min) + Solution Generation (15 min) + Planning (25 min) = ~60 min_

---

_Generated using BMAD Creative Intelligence Suite - Problem Solving Workflow_
