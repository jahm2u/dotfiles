You are an AI assistant tasked with reviewing existing GitHub issues and selecting the most appropriate task to work on next. Your goal is to analyze open issues, prioritize based on impact and complexity, then guide the implementation process.

<task_selection>
# $ARGUMENTS
</task_selection>

## 🤖 AI Tools Overview

Leverage these specialized AI tools throughout your development workflow:

**Core Analysis & Planning:**
- **chat** - Collaborative thinking and development conversations with o3/gemini
- **thinkdeep** - Extended reasoning and problem-solving for complex issues
- **planner** - Interactive sequential planning for complex projects
- **consensus** - Multi-model consensus analysis with stance steering

**Code & Quality:**
- **codereview** - Professional code review with severity levels
- **precommit** - Validate git changes before committing
- **debug** - Systematic investigation and debugging
- **analyze** - General-purpose file and code analysis
- **refactor** - Code refactoring with decomposition focus
- **tracer** - Static code analysis prompt generator for call-flow mapping
- **testgen** - Comprehensive test generation with edge case coverage

**Utility:**
- **listmodels** - Display all available AI models organized by provider
- **version** - Get server version and configuration

---

Follow these steps to select and implement the next task:

## 1. Review Open Issues
   - List all open issues: `gh issue list --repo [owner/repo] --state open --limit 20`
   - Examine issue labels, priorities, and dependencies
   - Check for any blocked or waiting issues
   - Note any critical bugs that need immediate attention

## 2. Analyze Task Priorities
   Consider these factors when prioritizing:
   - **Severity**: Critical bugs > Major bugs > Minor bugs > Enhancements
   - **User Impact**: How many users are affected?
   - **Business Value**: Does it unlock new capabilities or revenue?
   - **Technical Debt**: Will it make future work easier?
   - **Complexity**: Can it be completed in a reasonable timeframe?
   - **Dependencies**: Are there blockers or prerequisites?

   **🤖 AI Tool Recommendations:**
   - Use **consensus** with o3 and gemini for complex prioritization decisions:
     ```
     Get a consensus with o3 taking a supportive stance and gemini being critical 
     to evaluate which of these 3 high-priority issues we should tackle first
     ```
   - Use **thinkdeep** for extended analysis of complex technical decisions:
     ```
     Use thinkdeep with gemini pro to analyze the architectural implications 
     of implementing this feature versus the quick bug fix approach
     ```

## 3. Present Task Analysis
   Present your analysis in <task_analysis> tags including:
   - Top 3-5 candidate issues with brief descriptions
   - Pros/cons of working on each
   - Recommended task with justification
   - Estimated effort (hours/days)
   - Any risks or considerations

   **🤖 AI Tool Recommendations:**
   - Use **chat** for collaborative validation of your analysis:
     ```
     Chat with o3 about the best approach for prioritizing these database 
     performance issues versus the new user authentication feature
     ```

## 4. Implementation Planning
   Once a task is selected, create an implementation plan:
   - Break down the task into subtasks using TodoWrite
   - Identify files that need to be modified
   - List any new files or components to create
   - Note testing requirements
   - Consider edge cases and error handling

   **🤖 AI Tool Recommendations:**
   - Use **planner** for systematic breakdown of complex tasks:
     ```
     Use planner to break down this user authentication feature into manageable steps, 
     considering both frontend React components and backend API changes
     ```
   - For feature comparisons, use **planner** with parallel analysis:
     ```
     Create two separate sub-tasks: in one, use planner to show how to implement 
     OAuth authentication. In the other, use planner for JWT token authentication. 
     Once done, use consensus to get expert perspective from o3 and gemini on which 
     approach to implement first
     ```

## 5. Pre-Implementation Checklist
   Before starting coding:
   - [ ] Pull latest changes: `git pull origin main`
   - [ ] Create feature branch: `git checkout -b feature/issue-[number]-description`
   - [ ] Review related code and understand current implementation
   - [ ] Set up local testing environment if needed
   - [ ] Check for existing tests that might be affected

   **🤖 AI Tool Recommendations:**
   - Use **analyze** to understand existing code patterns:
     ```
     Analyze these authentication-related files to understand the current 
     implementation before adding new features
     ```
   - Use **tracer** for complex code flow analysis:
     ```
     Use tracer to generate static code analysis for understanding how user 
     sessions flow through the current authentication system
     ```

## 6. Implementation Guidelines
   During development:
   - **Use TodoWrite** to track progress on subtasks
   - **Read files before editing** to understand context
   - **Follow existing code patterns** and conventions
   - **Write clear commit messages** referencing the issue number
   - **Test changes locally** before committing
   - **Handle errors gracefully** with appropriate logging
   - **Update documentation** if behavior changes

   **🤖 AI Tool Recommendations:**
   - Use **debug** for systematic troubleshooting:
     ```
     The login button won't respond when clicked. Use debug with gemini pro 
     after gathering related component files to find the root cause
     ```
   - Use **refactor** to improve code quality during implementation:
     ```
     Use refactor to clean up this authentication service and improve its 
     maintainability while adding the new OAuth features
     ```

## 7. Code Quality Checks
   Before completing the task:
   - [ ] All acceptance criteria met
   - [ ] Code follows project style guide
   - [ ] No console.log or debug statements left
   - [ ] Error handling implemented
   - [ ] Edge cases considered
   - [ ] Performance impact assessed
   - [ ] Security implications reviewed

   **🤖 AI Tool Recommendations:**
   - Use **codereview** for professional code assessment:
     ```
     Use codereview to perform a comprehensive review of my authentication 
     changes with severity levels to ensure production readiness
     ```

## 8. Testing Requirements
   Ensure thorough testing:
   - Unit tests for new functions
   - Integration tests for API changes
   - Manual testing of UI changes
   - Regression testing of related features
   - Test with different data scenarios
   - Verify error messages are helpful

   **🤖 AI Tool Recommendations:**
   - Use **testgen** for comprehensive test coverage:
     ```
     Use testgen to generate comprehensive test suites for the new authentication 
     service with edge case coverage including error scenarios
     ```

## 9. Documentation Updates
   Update relevant documentation:
   - Code comments for complex logic
   - README.md if setup changes
   - CLAUDE.md if architecture changes
   - API documentation for endpoint changes
   - User-facing documentation if needed

## 10. Pull Request Preparation
   When ready to submit:
   - Review all changes: `git diff main`
   - Ensure commits are logical and atomic
   - Write comprehensive PR description
   - Link to the GitHub issue
   - Include testing instructions
   - Add screenshots for UI changes
   - Request review from appropriate team members

   **🤖 AI Tool Recommendations:**
   - Use **precommit** to validate changes before submission:
     ```
     Use precommit to validate my git changes for the authentication feature 
     before creating the pull request
     ```

⸻

## 🚀 Advanced AI Tool Usage Patterns

### 1. **chat** - General Development Chat & Collaborative Thinking
Your thinking partner for brainstorming, getting second opinions, and validating approaches. Perfect for technology comparisons, architecture discussions, and collaborative problem-solving.

**Example:**
```
Chat with o3 about the best approach for user authentication in my React app
```

### 2. **thinkdeep** - Extended Reasoning Partner
Get a second opinion to augment Claude's own extended thinking. Uses specialized thinking models to challenge assumptions, identify edge cases, and provide alternative perspectives.

**Example:**
```
The button won't animate when clicked, it seems something else is intercepting the clicks. 
Use thinkdeep with gemini pro after gathering related code and handing it the files 
and find out what the root cause is
```

### 3. **planner** - Interactive Step-by-Step Planning
Break down complex projects or ideas into manageable, structured plans through step-by-step thinking. Perfect for adding new features to an existing system, scaling up system design, migration strategies, and architectural planning with branching and revision capabilities.

**Pro Tip:** Claude supports sub-tasks where it will spawn and run separate background tasks. You can ask Claude to run planner with two separate ideas, then use consensus to get expert perspective from multiple AI models on which one to work on first!

**Example:**
```
Create two separate sub-tasks: in one, using planner tool show me how to add natural 
language support to my cooking app. In the other sub-task, use planner to plan how to 
add support for voice notes to my cooking app. Once done, start a consensus by sharing 
both plans to o3 and flash to give me the final verdict. Which one do I implement first?
```

### 4. **consensus** - Multi-Model Perspective Gathering
Get diverse expert opinions from multiple AI models on technical proposals and decisions. Supports stance steering (for/against/neutral) and structured decision-making.

**Example:**
```
Get a consensus with flash taking a supportive stance and gemini pro being critical to 
evaluate whether we should migrate from REST to GraphQL for our API. I need a 
definitive answer.
```

### 5. **Quick Tool Reference**
- **listmodels** - Check available AI models for any task
- **version** - Verify tool versions and configurations
- **analyze** - Quick file analysis for understanding code structure
- **tracer** - Generate call-flow maps for complex systems
- **debug** - Systematic debugging with specific model capabilities
- **refactor** - Code improvement with decomposition focus
- **testgen** - Automated test generation with edge cases
- **codereview** - Professional code review with severity assessment
- **precommit** - Pre-submission validation and checks

---

## Important Reminders:

### When Selecting Tasks:
- Prioritize tasks that unblock others
- Consider your current expertise and learning goals
- Balance quick wins with important long-term improvements
- Check if anyone is already working on similar issues

### During Implementation:
- Commit frequently with meaningful messages
- Ask for clarification if requirements are unclear
- Consider performance implications of changes
- Think about maintainability and future developers

### Common Pitfalls to Avoid:
- Don't modify code without understanding its purpose
- Don't ignore existing patterns for consistency
- Don't skip error handling to save time
- Don't forget to test edge cases
- Don't leave commented-out code in final commits

### Quick Commands Reference:
```bash
# View open issues
gh issue list --repo [owner/repo] --state open

# View specific issue
gh issue view [issue-number] --repo [owner/repo]

# Create branch for issue
git checkout -b feature/issue-[number]-description

# Check code changes
git diff main

# Run tests
npm test

# Check for linting issues
npm run lint

# View commit history
git log --oneline -10
```