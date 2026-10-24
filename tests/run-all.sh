#!/bin/bash
# Run the route D acceptance tests and print one table (F). Each test's full output
# goes to tests/results/run-<time>/NAME.log.
#   SKIP="name ..."   tests to leave out: a1 a2 a3-latency a3-avsync b-coldstart
#                     b-idle c1 e   (b-coldstart restarts the desktop; c1 takes
#                     about 15 minutes)
#   C1_ROUNDS         open/close rounds (default 100)
# Tests that show the display app (a3-*) are skipped while someone else holds the
# screen (/data/local/vm.lock, see lib/screen-free.sh).
here=$(cd "$(dirname "$0")" && pwd)
out="$here/results/run-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out"
rows=()

skip() { [[ " $SKIP " == *" $1 "* ]]; }
row() { rows+=("$1|$2|$3|$4"); printf '%-12s %-5s %s\n' "$1" "$3" "$4"; }

run() {  # name area command...: runs it, output to the log
    local name=$1 area=$2; shift 2
    if skip "$name"; then row "$name" "$area" SKIP "SKIP list"; return 1; fi
    "$@" > "$out/$name.log" 2>&1
    return 0
}

if run a1 A "$here/apps/run.sh"; then
    s=$(grep -E "^[0-9]+ apps:" "$out/a1.log")
    p95=$(grep -oE "P95 [0-9.]+ s" "$out/a1.log")
    if [ -n "$s" ] && ! echo "$s" | grep -qE "(fail|slow|timeout|crash) [1-9]"; then r=PASS; else r=FAIL; fi
    row a1 A $r "${s:-no summary}; $p95"
fi

if run a2 A "$here/lib/session-py.sh" core "$here/core/core_ops.py" 600; then
    n=$(grep -cE "^[a-z-]+ +PASS" "$out/a2.log"); t=$(grep -cE "^[a-z-]+ +(PASS|FAIL)" "$out/a2.log")
    [ "$t" -gt 0 ] && [ "$n" = "$t" ] && r=PASS || r=FAIL
    row a2 A $r "$n of $t core operations pass $(grep -E '^[a-z-]+ +FAIL' "$out/a2.log" | awk '{printf "(failed: %s) ", $1}')"
fi

if "$here/lib/screen-free.sh" 2> "$out/screen.log"; then
    if run a3-latency A "$here/audio/run.sh"; then
        worst=$(grep -oE "max [0-9]+ ms" "$out/a3-latency.log" | grep -oE "[0-9]+" | sort -n | tail -1)
        [ -n "$worst" ] && [ "$worst" -le 200 ] && r=PASS || r=FAIL
        row a3-latency A $r "$(grep -E '^(cold|warm):' "$out/a3-latency.log" | sed 's/:.*;/:/' | tr '\n' ' ')(target <= 200 ms)"
    fi
    if run a3-avsync A "$here/audio/avsync.sh"; then
        m=$(grep -oE "median [+-]?[0-9]+ ms" "$out/a3-avsync.log" | grep -oE "[+-]?[0-9]+")
        [ -n "$m" ] && [ "${m#[+-]}" -le 100 ] && r=PASS || r=FAIL
        row a3-avsync A $r "sound - picture: median ${m:-?} ms (target within 100 ms)"
    fi
else
    row a3 A SKIP "screen in use by someone else: $(head -c 120 "$out/screen.log" | tr '\n' ' ')"
fi

if run b-coldstart B "$here/perf/coldstart.sh"; then
    worst=$(grep -oE "background [0-9.]+ s" "$out/b-coldstart.log" | grep -oE "[0-9.]+" | sort -n | tail -1)
    awk -v w="${worst:-99}" 'BEGIN {exit !(w <= 10)}' && r=PASS || r=FAIL
    row b-coldstart B $r "desktop up in ${worst:-?} s at worst (target <= 10 s)"
fi

if run b-idle B "$here/perf/idle.sh"; then
    row b-idle B INFO "$(grep -E '^total:' "$out/b-idle.log" | sed 's/^total: //')"
fi

if run c1 C "$here/lib/session-py.sh" openclose "$here/stability/openclose.py" 2400 "${C1_ROUNDS:-100}"; then
    j=$(grep -E "^summary " "$out/c1.log" | sed 's/^summary //')
    r=$(echo "$j" | python3 -c 'import json,sys
try:
    s = json.load(sys.stdin)
except ValueError:
    print("FAIL|no summary"); sys.exit()
ok = s["no_window"] == 0 and s["growth_percent"] < 5
print("%s|%d rounds, %d without a window, memory %+.1f %%" % ("PASS" if ok else "FAIL", s["rounds"], s["no_window"], s["growth_percent"]))' 2>/dev/null || echo "FAIL|no summary")
    row c1 C "${r%%|*}" "${r#*|}"
fi

if run e E "$here/security/check.sh"; then
    f=$(grep -c "^FAIL" "$out/e.log"); p=$(grep -c "^PASS" "$out/e.log")
    [ "$f" = 0 ] && [ "$p" -gt 0 ] && r=PASS || r=FAIL
    row e E $r "$p pass, $f fail $(grep '^FAIL' "$out/e.log" | cut -d: -f1 | sed 's/^FAIL //' | tr '\n' ' ')"
fi

echo
echo "| Test | Area | Result | Detail |"
echo "|---|---|---|---|"
for x in "${rows[@]}"; do IFS='|' read -r n a r d <<< "$x"; echo "| $n | $a | $r | $d |"; done
echo
echo "logs: $out"
