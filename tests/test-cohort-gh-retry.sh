#!/bin/bash
# Self-test for the cold-start retry in bin/cohort-gh.
#
# Runs the real script against a fake `gh` placed first on PATH, inside a
# throwaway git repo whose origin decides the GH_HOST the script derives.
# The fake counts its own invocations in a file, so a case can fail a set
# number of times and then succeed.
#
# Usage: tests/test-cohort-gh-retry.sh
set -u

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cohort_gh="$repo_root/bin/cohort-gh"

sandbox=$(mktemp -d) || exit 1
trap 'rm -rf "$sandbox"' EXIT

failures=0

# A git repo with an origin, so the host-derivation logic ahead of the retry
# loop passes and hands a real GH_HOST to the fake gh.
workdir="$sandbox/repo"
git init -q "$workdir"
git -C "$workdir" remote add origin https://github.int.exe.xyz/samson212/cohort.git

# Every case gets a fresh bin so the invocation counter starts at zero.
# fail_times: how many attempts fail before one succeeds (>= attempts means
# it never succeeds). fail_msg goes to stderr, fail_code is the exit status.
make_fake_gh() {
    local fail_times=$1 fail_msg=$2 fail_code=$3
    fake_bin="$sandbox/bin"
    counter="$sandbox/count"

    rm -rf "$fake_bin"
    mkdir -p "$fake_bin"
    : > "$counter"

    cat > "$fake_bin/gh" <<EOF
#!/bin/bash
echo x >> "$counter"
n=\$(wc -l < "$counter")
if (( n <= $fail_times )); then
    echo "$fail_msg" >&2
    exit $fail_code
fi
# The success path prints to both streams: the test asserts stdout (gh's
# data) survives the buffering, and that GH_HOST still arrives intact.
echo "gh-stdout-payload GH_HOST=\${GH_HOST:-unset}"
echo "gh-stderr-note" >&2
exit 0
EOF
    chmod +x "$fake_bin/gh"
}

# Runs cohort-gh with the fake on PATH, capturing both streams and the status
# separately so each can be asserted on.
run_cohort_gh() {
    out_file="$sandbox/out"
    err_file="$sandbox/err"
    status=0
    ( cd "$workdir" && PATH="$fake_bin:$PATH" "$cohort_gh" "$@" ) \
        >"$out_file" 2>"$err_file" || status=$?
    out=$(< "$out_file")
    err=$(< "$err_file")
    calls=$(wc -l < "$counter")
    calls=$(( calls ))
}

check() {
    local label=$1 expected=$2 actual=$3
    if [[ "$expected" == "$actual" ]]; then
        echo "  ok: $label"
    else
        echo "  FAIL: $label"
        echo "        expected: $expected"
        echo "        actual:   $actual"
        failures=$(( failures + 1 ))
    fi
}

check_contains() {
    local label=$1 needle=$2 haystack=$3
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  ok: $label"
    else
        echo "  FAIL: $label"
        echo "        expected to contain: $needle"
        echo "        actual:              $haystack"
        failures=$(( failures + 1 ))
    fi
}

check_lacks() {
    local label=$1 needle=$2 haystack=$3
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "  ok: $label"
    else
        echo "  FAIL: $label"
        echo "        expected NOT to contain: $needle"
        echo "        actual:                  $haystack"
        failures=$(( failures + 1 ))
    fi
}

echo "case: success on first attempt makes exactly one call"
make_fake_gh 0 "" 0
run_cohort_gh pr list
check "exit status" 0 "$status"
check "gh invocations" 1 "$calls"
check_contains "gh stdout passes through" "gh-stdout-payload" "$out"
check_contains "GH_HOST still derived from origin" "GH_HOST=github.int.exe.xyz" "$out"
check_contains "gh stderr passes through" "gh-stderr-note" "$err"
check_lacks "no retry noise on the success path" "retrying" "$err"

echo "case: HTTP 503 retries and then succeeds"
make_fake_gh 1 "HTTP 503: Service Unavailable" 1
run_cohort_gh pr list
check "exit status" 0 "$status"
check "gh invocations" 2 "$calls"
check_contains "gh stdout of the winning attempt" "gh-stdout-payload" "$out"
check_lacks "failed attempt's stderr is not replayed" "HTTP 503" "$err"
check_contains "retry is announced on stderr" "retrying in 1s (attempt 2/3)" "$err"

echo "case: 502 and 504 are transient too"
for code in 502 504; do
    make_fake_gh 1 "HTTP $code: upstream error" 1
    run_cohort_gh api repos/samson212/cohort
    check "exit status ($code)" 0 "$status"
    check "gh invocations ($code)" 2 "$calls"
done

echo "case: the proxy's 403 cold-start body is transient"
make_fake_gh 2 "HTTP 403: integration not found or not attached to this VM (trace: abc123)" 1
run_cohort_gh repo view samson212/cohort
check "exit status" 0 "$status"
check "gh invocations exhaust both retries" 3 "$calls"
check_contains "gh stdout of the winning attempt" "gh-stdout-payload" "$out"

echo "case: a by-design 403 is permanent and is not retried"
make_fake_gh 99 "HTTP 403: path does not match any configured repository" 1
run_cohort_gh api /user
check "exit status passes through" 1 "$status"
check "gh invoked exactly once" 1 "$calls"
check_contains "real gh error reaches the user" "path does not match any configured repository" "$err"
check_lacks "no retry attempted" "retrying" "$err"

echo "case: an ordinary gh failure is permanent and is not retried"
make_fake_gh 99 "gh: To get started with GitHub CLI, please run: gh auth login" 4
run_cohort_gh pr list
check "exit status passes through" 4 "$status"
check "gh invoked exactly once" 1 "$calls"
check_contains "real gh error reaches the user" "gh auth login" "$err"
check_lacks "no retry attempted" "retrying" "$err"

echo "case: retries are bounded and the final failure is gh's own"
make_fake_gh 99 "HTTP 503: Service Unavailable" 7
run_cohort_gh pr list
check "exit status passes through" 7 "$status"
check "gh invoked exactly 3 times" 3 "$calls"
check_contains "last attempt's real error reaches the user" "HTTP 503: Service Unavailable" "$err"

echo
if (( failures == 0 )); then
    echo "PASS: all assertions passed"
    exit 0
fi
echo "FAIL: $failures assertion(s) failed"
exit 1
