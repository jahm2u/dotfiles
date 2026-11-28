#!/bin/bash
# gates.test.sh: health.sh (launch admission) and sweep.sh (what may be closed) against fixtures.
# No MBP needed. Prints PASS/FAIL per check and "ran N checks, M failed"; exit = M.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
n=0 failed=0
check() { n=$((n + 1)); if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; failed=$((failed + 1)); fi; }

health() { printf '%s\n' "$@" > "$T/h"; out=$(MBP_HEALTH_FILE="$T/h" bash "$here/health.sh" 2>&1); rc=$?; }
ok=(free=40 swap_mb=0 load5=10 ncpu=14 claude=12 builders=5)

health "${ok[@]}"
check "H1 a quiet MBP is admitted" '[ $rc = 0 ] && grep -q ADMIT <<<"$out"'
health free=12 swap_mb=0 load5=10 ncpu=14 claude=12 builders=5
check "H2 low free memory refuses" '[ $rc = 1 ] && grep -q "free memory 12%" <<<"$out"'
health free=40 swap_mb=9000 load5=10 ncpu=14 claude=12 builders=5
check "H3 heavy swap refuses (the 2026-11-27 panic state)" '[ $rc = 1 ] && grep -q "swap in use 9000M" <<<"$out"'
health free=40 swap_mb=0 load5=47 ncpu=14 claude=12 builders=5
check "H4 load 47 on 14 cores refuses" '[ $rc = 1 ] && grep -q "5-min load 47" <<<"$out"'
health free=40 swap_mb=0 load5=10 ncpu=14 claude=12 builders=10
check "H5 builder cap refuses at the cap" '[ $rc = 1 ] && grep -q "10 builder workspaces, cap 10" <<<"$out"'
health free=40 swap_mb=0 load5=10 ncpu=14 claude=30 builders=5
check "H6 claude cap refuses" '[ $rc = 1 ] && grep -q "30 claude processes" <<<"$out"'
health free=40 load5=10 ncpu=14 claude=12 builders=5
check "H7 an unreadable number refuses, never admits" '[ $rc = 2 ] && grep -q "could not read swap" <<<"$out"'
health free=5 swap_mb=9000 load5=47 ncpu=14 claude=40 builders=12
check "H8 every reason is printed" '[ "$(grep -c "^REFUSE" <<<"$out")" = 5 ]'

# sweep fixtures: workspaces (ws slug status), ledgers (slug ws repo lbr cur dirty onr orch), prs (slug state)
F="$T/sw"; mkdir -p "$F"
tab=$'\t'
cat > "$F/workspaces" <<EOF
wA${tab}dup-idle${tab}idle
wA2${tab}dup-idle${tab}unknown
wB${tab}dup-idle${tab}done
wC${tab}dup-busy${tab}working
wD${tab}dup-busy${tab}idle
wE${tab}merged-clean${tab}idle
wF${tab}merged-dirty${tab}idle
wG${tab}live${tab}working
wH${tab}stray${tab}idle
wI${tab}merged-busy${tab}working
EOF
cat > "$F/ledgers" <<EOF
dup-idle${tab}wB${tab}o/r${tab}b1${tab}b1${tab}0${tab}yes${tab}orch1
dup-busy${tab}wD${tab}o/r${tab}b2${tab}b2${tab}0${tab}yes${tab}orch1
merged-clean${tab}wE${tab}o/r${tab}b3${tab}b3-diag${tab}0${tab}yes${tab}orch2
merged-dirty${tab}wF${tab}o/r${tab}b4${tab}b4${tab}3${tab}yes${tab}orch2
merged-busy${tab}wI${tab}o/r${tab}b7${tab}b7${tab}0${tab}yes${tab}orch2
live${tab}wG${tab}o/r${tab}b5${tab}b5${tab}2${tab}no${tab}orch3
parked${tab}wZ${tab}o/r${tab}b6${tab}b6${tab}0${tab}yes${tab}orch3
EOF
printf 'merged-clean\tMERGED\nmerged-dirty\tMERGED\nmerged-busy\tMERGED\nlive\tOPEN\nparked\tOPEN\n' > "$F/prs"

out=$(SWEEP_FIXTURE_DIR="$F" bash "$here/sweep.sh" 2>&1)
check "S1 dry run closes nothing" '[ ! -e "$F/applied" ]'
check "S2 idle duplicate is SAFE" 'grep -q "^SAFE    DUP wA dup-idle" <<<"$out"'
check "S3 a working duplicate is never SAFE" 'grep -q "^WORKING wC dup-busy" <<<"$out" && ! grep -q "SAFE.*wC" <<<"$out"'
check "S4 the ledger workspace itself is not a duplicate" '! grep -qE "DUP (wB|wD|wE|wG) " <<<"$out"'
check "S5 merged, clean, on remote is SAFE (current branch, not ledger branch)" 'grep -q "^SAFE    MERGED merged-clean (b3-diag)" <<<"$out"'
check "S6 merged but dirty is for a person" 'grep -q "^MERGED? merged-dirty: PR merged but dirty=3" <<<"$out"'
check "S7 merged but working is never SAFE" 'grep -q "^WORKING merged-busy" <<<"$out" && ! grep -q "SAFE.*merged-busy" <<<"$out"'
check "S8 open PR is left alone" '! grep -q " live" <<<"$out"'
check "S9 workspace with no ledger is ORPHAN, reported" 'grep -q "^ORPHAN  wH stray" <<<"$out"'
check "S10 ledger with no workspace is NOPANE, reported" 'grep -q "^NOPANE  parked" <<<"$out"'
check "S11 summary counts" 'grep -q "sweep: 3 safe to close (dry run" <<<"$out"'

SWEEP_FIXTURE_DIR="$F" bash "$here/sweep.sh" --apply >/dev/null 2>&1
check "S12 --apply closes every SAFE one, not just the first (stdin not swallowed)" '[ "$(sort "$F/applied" | tr "\n" ",")" = "builder merged-clean,ws wA,ws wA2," ]'

echo "ran $n checks, $failed failed"
exit "$failed"
