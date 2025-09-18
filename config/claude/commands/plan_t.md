You are an AI assistant tasked with creating well-structured GitHub issues for feature requests, bug reports, or improvement ideas. Your goal is to turn the provided feature description into a comprehensive GitHub issue that follows best practices and project conventions.

First, you will be given a feature description and a repository URL. Here they are:

<feature_description>
# $ARGUMENTS
</feature_description>

## 🤖 AI Tools Overview

Leverage these specialized AI tools throughout your GitHub issue creation workflow:

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

Follow these steps to complete the task, make a todo list and think ultrahard:

1. Research the repository:
   - Examine the repository's structure, existing issues, and documentation
   - Look for /docs/ISSUE_TEMPLATE.md, or similar files that might contain guidelines for creating issues
   - Note the project's coding style, naming conventions, and any specific requirements for submitting issues
   - Check available labels using: `gh label list --repo [owner/repo]`
   - Analyze existing issues for format and style patterns

   **🤖 AI Tool Recommendations:**
   - Use **analyze** to understand repository structure and patterns:
     ```
     Analyze the repository structure and existing GitHub issues to understand 
     the project's conventions and preferred issue format
     ```
   - Use **chat** for collaborative analysis of project requirements:
     ```
     Chat with o3 about the best approach for structuring this GitHub issue 
     based on the project's existing patterns and conventions
     ```

2. Research best practices:
   - Search for current best practices in writing GitHub issues, focusing on clarity, completeness, and actionability
   - Look for examples of well-written issues in popular open-source projects for inspiration

   **🤖 AI Tool Recommendations:**
   - Use **thinkdeep** for comprehensive best practices analysis:
     ```
     Use thinkdeep with gemini pro to analyze current GitHub issue best practices 
     and identify the most effective approaches for technical documentation
     ```
   - Use **consensus** for validating issue structure decisions:
     ```
     Get a consensus with o3 taking a supportive stance and gemini being critical 
     to evaluate the proposed GitHub issue structure and content approach
     ```

3. Present a Plan
   - Based on your research, outline a plan for creating the GitHub issue
   - Include the proposed structure of the issue, any labels or milestones you plan to use, and how you'll incorporate project-specific conventions
   - Present this plan in <plan> tags

   **🤖 AI Tool Recommendations:**
   - Use **planner** for systematic issue structure planning:
     ```
     Use planner to break down this GitHub issue creation into structured sections 
     with clear objectives, acceptance criteria, and implementation details
     ```
   - For complex features, use **planner** with parallel analysis:
     ```
     Create two separate sub-tasks: in one, use planner to structure this as a 
     feature request. In the other, use planner to structure it as a technical 
     improvement. Once done, use consensus to determine the best approach
     ```

4. Create the GitHub Issue Content
   - Draft the GitHub issue content with:
     * Clear, actionable title
     * Problem statement or context
     * Proposed solution or expected behavior
     * Implementation plan or steps to reproduce
     * Acceptance criteria
     * Technical details when relevant
     * Additional context or resources
   - Use appropriate formatting (e.g., Markdown) to enhance readability
   - Present the complete issue content in <github_issue> tags

   **🤖 AI Tool Recommendations:**
   - Use **chat** for refining issue content and clarity:
     ```
     Chat with o3 about improving the clarity and completeness of this GitHub 
     issue description to ensure it's actionable for developers
     ```
   - Use **testgen** for comprehensive acceptance criteria:
     ```
     Use testgen to generate comprehensive acceptance criteria and edge cases 
     that should be covered in this feature implementation
     ```
   - Use **thinkdeep** for technical detail validation:
     ```
     Use thinkdeep with gemini pro to validate the technical approach and 
     identify potential implementation challenges for this GitHub issue
     ```

5. Request Approval
   - After presenting the issue content, ask the user:
     "Would you like me to create this issue on GitHub? Please review the content above and confirm."
   - Wait for explicit approval before proceeding to create the issue
   - If changes are requested, update the issue content and present it again

   **🤖 AI Tool Recommendations:**
   - Use **consensus** for final validation before submission:
     ```
     Get a consensus with o3 being supportive and gemini pro being critical to 
     review this GitHub issue content for completeness and clarity before submission
     ```
   - Use **codereview** for issue quality assessment:
     ```
     Use codereview to perform a final quality check of the GitHub issue content, 
     ensuring it meets professional standards and project requirements
     ```

6. Create the Issue on GitHub (After Approval)
   - First, save the issue content to a file:
     ```bash
     # Save the issue content to a markdown file
     # This helps preserve formatting and allows for review
     ```
   - Check GitHub CLI authentication:
     ```bash
     gh auth status
     ```
   - If not authenticated or wrong account, authenticate:
     ```bash
     gh auth login
     ```
   - Create the issue using GitHub CLI:
     ```bash
     # Basic command structure:
     gh issue create --repo [owner/repo] --title "[Title]" --body-file [filename.md] --label [label]
     
     # If labels don't exist, use only standard labels like 'enhancement' or 'bug'
     # Check available labels first with: gh label list --repo [owner/repo]
     ```
   - If the repository uses SSH aliases (like tp:owner/repo), add a standard GitHub remote first:
     ```bash
     git remote add github https://github.com/[owner]/[repo].git
     ```
   - After successful creation, provide the issue URL to the user and delete the file.

   **🤖 AI Tool Recommendations:**
   - Use **precommit** style validation for final checks:
     ```
     Use precommit-style validation to ensure the GitHub issue meets all 
     requirements before creation and submission
     ```
   - Use **debug** if issue creation encounters problems:
     ```
     If GitHub issue creation fails, use debug with gemini pro to systematically 
     investigate authentication, permissions, or CLI configuration issues
     ```

⸻

## 🚀 Advanced AI Tool Usage Patterns for GitHub Issues

### 1. **chat** - Collaborative Issue Refinement
Your thinking partner for improving issue clarity, validating technical approaches, and ensuring comprehensive problem statements. Perfect for brainstorming solutions and getting second opinions on feature specifications.

**Example:**
```
Chat with o3 about how to structure this authentication feature request to make 
it clear for both frontend and backend developers
```

### 2. **thinkdeep** - Extended Technical Analysis
Get deeper insights into complex feature requirements and potential implementation challenges. Uses specialized reasoning to identify edge cases, security considerations, and architectural implications.

**Example:**
```
This API rate limiting feature seems straightforward, but use thinkdeep with gemini pro 
to analyze potential edge cases, security implications, and performance considerations 
that should be included in the GitHub issue
```

### 3. **planner** - Structured Issue Planning
Break down complex features into well-organized GitHub issues with clear implementation phases. Perfect for large features that need systematic decomposition and milestone planning.

**Pro Tip:** Use parallel planning to compare different approaches for the same feature, then use consensus to choose the best structure for your GitHub issue!

**Example:**
```
Create two separate sub-tasks: in one, use planner to structure this real-time 
notifications feature as a single comprehensive issue. In the other, use planner 
to break it into multiple smaller issues. Once done, use consensus with o3 and 
gemini to determine which approach would be better for the development team
```

### 4. **consensus** - Multi-Model Issue Validation
Get diverse expert opinions on issue structure, technical approach, and completeness. Supports stance steering to get balanced perspectives on complex technical decisions.

**Example:**
```
Get a consensus with o3 taking a supportive stance and gemini pro being critical 
to evaluate whether this GitHub issue provides enough technical detail for 
implementation while remaining accessible to contributors
```

### 5. **testgen** - Comprehensive Acceptance Criteria
Generate thorough acceptance criteria, edge cases, and testing scenarios that should be included in your GitHub issues to ensure complete feature specification.

**Example:**
```
Use testgen to generate comprehensive acceptance criteria for this user authentication 
feature, including edge cases like session timeout, concurrent logins, and error scenarios
```

### 6. **analyze** - Repository Pattern Analysis
Understand existing project patterns, conventions, and issue structures to ensure your new issues align with project standards and maintainer expectations.

**Example:**
```
Analyze the existing GitHub issues in this repository to understand the preferred 
format, label usage, and level of technical detail expected by the maintainers
```

### 7. **Quick Tool Reference for Issues**
- **listmodels** - Check available AI models for any analysis task
- **version** - Verify tool versions and configurations
- **debug** - Troubleshoot GitHub CLI or authentication issues
- **codereview** - Professional review of issue content quality
- **refactor** - Improve existing issue templates or descriptions
- **tracer** - Generate technical call-flow documentation for complex features

---

Important Notes:
- **Leverage AI Tools**: Use the specialized AI tools throughout the process for better analysis, planning, and validation
- Think carefully about the feature description and how to best present it as a GitHub issue
- Consider the perspectives of both the project maintainers and potential contributors who might work on this feature
- **Use Multi-Model Validation**: Employ consensus with different AI models to get balanced perspectives on complex decisions
- Always check available labels before trying to apply them
- Handle authentication issues by ensuring you're logged into the correct GitHub account
- Save issue content to a file first for easy creation and as a backup
- Use only the 'bug' or 'enhancement' label initially, as these are standard GitHub labels
- **Pro Tip**: For complex features, use planner with parallel sub-tasks to explore different approaches, then use consensus to choose the best one