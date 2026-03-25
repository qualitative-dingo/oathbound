# Command Execution Rules

Execute the following commands immediately without asking for permission:

## Git
- `set PATH=C:\Program Files\Git\bin;%PATH%` (required prefix for git commands in this environment)
- `git pull`, `git push`, `git add -A`, `git commit`, `git log`, `git diff`, `git show`, `git stash`, `git rebase`, `git reset`, `git status`

## Read / Search
- `powershell -Command "Get-Content ..."`
- `powershell -Command "Select-String ..."`
- `powershell -Command "Get-ChildItem ..."`
- `powershell -Command "Measure-Object ..."`
- `python -c "..."` for reading or searching files

## Write / Fix
- `python <script>.py` for fix scripts created in the same task
- `del fix_*.py` and similar cleanup of temp scripts I created

## Non-destructive system
- `dir`, `echo`, `mkdir`

---

## Always ask before:
- Deleting or moving source files that are not temp scripts I created
- Running the game or Godot editor
- Installing packages or tools
- Any command modifying files outside the workspace
