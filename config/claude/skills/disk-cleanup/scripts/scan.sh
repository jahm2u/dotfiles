#!/bin/bash
# Read-only triage of every git worktree under the given roots, plus the big caches.
# Never deletes anything. Usage: scan.sh [root ...]   (default: ~/repos ~/work)
#
# Verdicts:
#   SAFE  PR merged at this exact HEAD (or HEAD already in origin's default branch),
#         nothing uncommitted, no process running inside. Remove without asking each one.
#   ASK   recoverable but a human should say so: closed PR, no PR, untracked files only.
#   KEEP  uncommitted changes, commits on no remote, open PR, or a live process inside.
#
# Lessons baked in (2026-10-17 cleanup):
#   - Squash merges leave the branch's commits on no remote once GitHub deletes the
#     branch, so "unpushed" alone does not mean unsaved: compare HEAD to the PR head.
#   - "Nothing ahead and no PR" is NOT safe: liaison checkouts (local/ex, local/mt...)
#     look exactly like that and are in use.
#   - watchman drops .watchman-cookie-* files into roots it watches; they are not work.
#   - Directory mtime is meaningless (watchman touches it); age = last commit.

ROOTS=("$@")
[[ ${#ROOTS[@]} -eq 0 ]] && ROOTS=("$HOME/repos" "$HOME/work")

FIND=/usr/bin/find
DU=/usr/bin/du
NOW=$(date +%s)

# cwd of every running process, to spot worktrees in use
LIVE_CWDS=$(lsof -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | sort -u)

in_use() {  # $1 = worktree path; prints the first command running inside it
    local wt=$1 pid
    grep -qE "^${wt}(/|$)" <<<"$LIVE_CWDS" || return 1
    pid=$(lsof -d cwd 2>/dev/null | awk -v w="$wt" '$NF==w || index($NF, w"/")==1 {print $2; exit}')
    ps -o comm= -p "$pid" 2>/dev/null | xargs basename 2>/dev/null
}

ROWS=$(mktemp)
{

PRIMARIES=$(for r in "${ROOTS[@]}"; do
    [[ -d "$r" ]] && $FIND "$r" -maxdepth 7 \( -name node_modules -o -path '*/.claude/worktrees' \) -prune \
        -o -type d -name .git -print 2>/dev/null
done | sed 's|/\.git$||' | sort -u)

SEEN=$(mktemp); REGISTERED=$(mktemp)
while IFS= read -r primary; do
    [[ -z "$primary" ]] && continue
    primary_real=$(cd "$primary" && pwd -P)
    grep -qxF "$primary_real" "$SEEN" && continue
    echo "$primary_real" >> "$SEEN"

    # Stale registrations (dir gone): git can prune them for free
    git -C "$primary" worktree prune --dry-run -v 2>/dev/null | sed -n 's/^Removing worktrees\/\([^:]*\):.*/\1/p' | while read -r name; do
        printf 'SAFE\t0\t-\t-\tregistration only, dir is gone (git worktree prune)\t%s [%s]\n' "$primary" "$name"
    done

    slug=$(cd "$primary" && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
    default=$(git -C "$primary" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)

    git -C "$primary" worktree list --porcelain 2>/dev/null | awk '
        /^worktree /{p=substr($0,10)} /^branch /{b=substr($0,19)} /^detached/{b="(detached)"}
        /^$/{print p"\t"b; p=""; b=""}' |
    while IFS=$'\t' read -r wt branch; do
        [[ -d "$wt" ]] || continue
        wt_real=$(cd "$wt" && pwd -P)
        [[ "$wt_real" == "$primary_real" ]] && continue
        echo "$wt_real" >> "$REGISTERED"

        size=-   # filled in afterwards, see SIZES
        last=$(git -C "$wt" log -1 --format=%ct 2>/dev/null || echo "$NOW")
        age="$(( (NOW - last) / 86400 ))d"
        status=$(git -C "$wt" status --porcelain 2>/dev/null | grep -v '\.watchman-cookie-')
        tracked=$(grep -vc '^??' <<<"$status" | tr -d ' '); [[ -z "$status" ]] && tracked=0
        untracked=$(grep -c '^??' <<<"$status" | tr -d ' ')
        head=$(git -C "$wt" rev-parse HEAD 2>/dev/null)
        on_remote_count=$(git -C "$wt" rev-list --count HEAD --not --remotes 2>/dev/null || echo 0)
        in_default=$(git -C "$wt" merge-base --is-ancestor HEAD "$default" 2>/dev/null && echo yes)
        ahead=$(git -C "$wt" rev-list --count "$default..HEAD" 2>/dev/null || echo "?")

        pr_state="" pr_num="" pr_head=""
        if [[ -n "$slug" && "$branch" != "(detached)" ]]; then
            read -r pr_num pr_state pr_head < <(gh pr list -R "$slug" --head "$branch" --state all \
                --json number,state,headRefOid -q '.[0] // empty | "\(.number) \(.state) \(.headRefOid)"' 2>/dev/null)
        fi
        pr="${pr_num:+PR #$pr_num $pr_state}"; pr=${pr:-no PR}

        proc=$(in_use "$wt_real")
        verdict="" why=""
        if [[ -n "$proc" ]]; then
            verdict=KEEP; why="in use by $proc"
        elif [[ "$tracked" -gt 0 ]]; then
            verdict=KEEP; why="$tracked uncommitted changes; $pr"
        elif [[ "$pr_state" == OPEN ]]; then
            verdict=KEEP; why="$pr"
        elif [[ "$pr_state" == MERGED && "$pr_head" == "$head" ]] || [[ -n "$in_default" ]]; then
            if [[ "$untracked" -gt 0 ]]; then
                verdict=ASK; why="${pr}, but $untracked untracked files"
            else
                verdict=SAFE; why="${in_default:+in $default}${in_default:+; }$pr"
                # cmux builders live at .claude/worktrees/wt-<slug>: the collector also archives spec + log
                [[ "$wt_real" == */.claude/worktrees/wt-* ]] && why="$why; cmux builder, use /cmux-trash-collector ${wt_real##*/wt-}"
            fi
        elif [[ "$on_remote_count" -gt 0 ]]; then
            verdict=KEEP; why="$on_remote_count commits on no remote; $pr"
        else
            verdict=ASK; why="$pr; $ahead ahead of $default, all pushed (no PR + nothing ahead can be a long-lived checkout)"
            [[ "$untracked" -gt 0 ]] && why="$why; $untracked untracked files"
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$verdict" "$size" "$age" "$branch" "$why" "$wt"
    done
done <<<"$PRIMARIES"

# Orphans: dirs under .claude/worktrees (or named *.stale*) that no repo registers
for r in "${ROOTS[@]}"; do
    [[ -d "$r" ]] || continue
    { $FIND "$r" -maxdepth 8 -name node_modules -prune -o -type d -path '*/.claude/worktrees/*' -prune -print 2>/dev/null
      $FIND "$r" -maxdepth 4 -name node_modules -prune -o -type d -name '*.stale*' -prune -print 2>/dev/null; } |
    while IFS= read -r d; do
        d_real=$(cd "$d" && pwd -P)
        grep -qxF "$d_real" "$REGISTERED" && continue
        proc=$(in_use "$d_real")
        verdict=ASK; why="orphan: not a registered worktree"
        [[ -n "$proc" ]] && { verdict=KEEP; why="orphan, but in use by $proc"; }
        printf '%s\t%s\t-\t-\t%s\t%s\n' "$verdict" - "$why" "$d"
    done
done
} > "$ROWS"

# du is the slow part (~50 s for a 1.8 GB checkout here: metadata latency, not CPU), so only
# size the rows a human will decide on, in parallel. A KEEP row's size changes nothing.
SIZES=$(mktemp)
awk -F'\t' '$1!="KEEP" && $6 !~ / \[/ {print $6}' "$ROWS" | tr '\n' '\0' |
    xargs -0 -P 8 -n 1 $DU -sh 2>/dev/null > "$SIZES"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' VERDICT SIZE AGE BRANCH WHY PATH
awk -F'\t' -v OFS='\t' 'NR==FNR {s[$2]=$1; next} {if ($6 in s) $2=s[$6]; print}' "$SIZES" "$ROWS"
rm -f "$SEEN" "$REGISTERED" "$ROWS" "$SIZES"

echo
echo "CACHES (all regenerate on demand)"
for c in "$HOME/.npm" "$HOME/Library/Caches/CocoaPods" "$HOME/.cache/uv" "$HOME/.cache/puppeteer" \
         "$HOME/Library/Caches/ms-playwright" "$HOME/Library/Developer/Xcode/DerivedData" \
         "$HOME/Library/Developer/Xcode/iOS DeviceSupport" "$HOME/Library/Developer/CoreSimulator/Caches" \
         "$HOME/Library/Caches/pip" "$HOME/.Trash" "$HOME/Library/Application Support/Claude/vm_bundles"; do
    [[ -e "$c" ]] && printf '%s\t%s\n' "$($DU -sh "$c" 2>/dev/null | cut -f1)" "$c"
done

echo
echo "DISK"
df -h /System/Volumes/Data | awk 'NR==2 {print "free " $4 " of " $2 " (" $5 " used)"}'
echo "local TM snapshots: $(tmutil listlocalsnapshots / 2>/dev/null | grep -c TimeMachine)"
