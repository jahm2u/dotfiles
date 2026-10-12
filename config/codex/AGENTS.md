# Global instructions (all Codex sessions on this machine)

## Stay inside the repository

Work only inside the git repository (or directory) you were started in.

- Never run `find`, `rg`, `grep -r`, `ls -R`, `fd` or `du` on `/`, `/Users`, `$HOME`, `~`,
  `~/Library`, `~/Pictures`, `~/Documents`, `~/Desktop` or a parent of the working directory.
  Walking the home folder triggers macOS privacy prompts on the user's screen.
- If a skill, config or tool you expect is not in the repository or in your listed skills, do not
  search the machine for it. Say it is missing and continue.
- For code review, use the `review` skill. There is no other review skill to find.
