TestGen Async Processing Workflow

🚀 TESTGEN-DRIVEN PROCESSING - EXPLICIT COMMAND STRUCTURE

CRITICAL: Use npm test to identify failing files.
Create async tasks via TestGen (ZenMCP) for parallel file regeneration with comprehensive test suites.
CONTINUOUS EXECUTION - 5 tasks at a time until complete.

⚠️ CLAUDE’S ROLE: COORDINATOR ONLY

CLAUDE MUST NOT DIRECTLY PROCESS TEST FILES.
Always delegate tasks asynchronously using TestGen ZenMCP.

⸻

📋 TestGen Command Workflow (4 Steps)

Step 1: Identify Failing Tests - LOCAL PROCESSING

npm test
# Capture output of failing tests
# Generate a list of affected files (70+ files)
npm test -- --json --outputFile=failed-tests.json

Step 2: Prepare Async Task Generation via TestGen - LOCAL PROCESSING

# CRITICAL: Parse failing tests and create task queue
node -e "
const fs = require('fs');
const results = JSON.parse(fs.readFileSync('failed-tests.json'));
const failedFiles = results.testResults.filter(t => t.status === 'failed').map(t => t.name);
fs.writeFileSync('failed-files.txt', failedFiles.join('\n'));
console.log(`Total failing files: ${failedFiles.length}`);
"

Step 3: Async Task Execution via TestGen ZenMCP - CONTINUOUS (5 at a time)

# CRITICAL: Continuously execute TestGen ZenMCP for async regeneration of tests
cat failed-files.txt | xargs -P 5 -I {} bash -c '
  rm {};
  zen:testgen write me tests for file {} --output {};
  echo "Regenerated comprehensive test suite for: {}";
  npm test {} || zen:testgen feedback "Test failed for file {}, please regenerate with fixes";
'

Step 4: Immediate Verification via npm Test (Single File)

# Re-run test immediately after regeneration to ensure individual issue resolved
npm test <file_name>
# Provide feedback to TestGen if issues persist


⸻

🛠️ Commands: npm test | zen:testgen

TestGen ZenMCP Command Structure:
	•	npm test - To identify failing tests
	•	zen:testgen - Regenerate comprehensive test files asynchronously
	•	Async Execution - xargs -P 5 to run five tasks concurrently

File Path Structure:

FAILING_TEST_LIST: failed-files.txt
REGENERATED_TESTS: Same file names, regenerated via zen:testgen


⸻

🔄 TestGen Processing Flow

STEP 1: IDENTIFY FAILURES LOCALLY - npm test
	•	Generate JSON report with failing test files

STEP 2: CREATE TASK QUEUE - Local Node.js script
	•	Parse failing tests from JSON to text file

STEP 3: ASYNC REGENERATION - zen:testgen
	•	Delete failed test files and regenerate via ZenMCP TestGen
	•	Run 5 async tasks continuously until all complete
	•	Immediately test each regenerated file, provide feedback if failing

STEP 4: IMMEDIATE CONFIRMATION - npm test
	•	Verify individual regenerated tests pass immediately
	•	Provide feedback to TestGen ZenMCP for any unresolved issues

⸻

🚨 CRITICAL RULES
	1.	LOCAL IDENTIFICATION ONLY - npm test for identifying failing files
	2.	ASYNCHRONOUS EXECUTION - Continuously process 5 files concurrently
	3.	EXPLICIT COMMANDS - zen:testgen to regenerate comprehensive tests
	4.	NO DIRECT FILE PROCESSING - Claude coordinates only, never direct file edits
	5.	IMMEDIATE VERIFICATION & FEEDBACK - Re-run individual tests immediately and feedback any failures

🎯 Expected Output
	•	Comprehensive test suites regenerated and passing
	•	Continuous, efficient async processing
	•	Immediate feedback loop for resolving persistent failures
	•	Zero manual editing, maximum delegation