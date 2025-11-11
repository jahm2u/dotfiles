#!/Users/v/.config/sketchybar/venv/bin/python3
"""
Syntax check test for all modified files
"""
import ast
import sys
from pathlib import Path

def check_python_syntax(file_path):
    """Check if a Python file has valid syntax"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            code = f.read()
        ast.parse(code)
        return True, None
    except SyntaxError as e:
        return False, f"Line {e.lineno}: {e.msg}"
    except Exception as e:
        return False, str(e)

def main():
    """Test all modified Python files"""
    helpers_dir = Path(__file__).parent

    files_to_check = [
        "analyze-meeting-history.py",
        "generate-meeting-note.py",
        "classify-meeting-unified.py"
    ]

    print("Running syntax checks on modified files...")
    print("=" * 80)

    all_passed = True
    for filename in files_to_check:
        file_path = helpers_dir / filename
        if not file_path.exists():
            print(f"❌ {filename}: File not found")
            all_passed = False
            continue

        passed, error = check_python_syntax(file_path)
        if passed:
            print(f"✓ {filename}: Syntax OK")
        else:
            print(f"❌ {filename}: Syntax Error")
            print(f"   {error}")
            all_passed = False

    print("=" * 80)

    if all_passed:
        print("✅ All files passed syntax check!")
        return 0
    else:
        print("❌ Some files have syntax errors")
        return 1

if __name__ == "__main__":
    sys.exit(main())
