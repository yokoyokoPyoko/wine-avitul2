#!/bin/bash
# CPU/wchan sampler for hung or slow AviUtl2 playback threads.
# Usage: play video, press Space, then IMMEDIATELY run:
#   bash ~/Program/Cpp/Wine_Aviutl2_Adapter/logs/sample_cpu.sh [seconds, default 12]
# Paste back the whole output (about 20 lines).
set -u
DUR=${1:-12}

P=""
for p in $(pgrep -f "viutl2[.]exe" 2>/dev/null); do
    if [ "$p" != "$$" ] && [ "$p" != "$PPID" ]; then P="$p"; break; fi
done
[ -z "$P" ] && { echo "aviutl2.exe not found (is it running?)"; exit 1; }
echo "sampling pid=$P for ${DUR}s..."

sample() {
    for t in /proc/$P/task/*; do
        tid=${t##*/}
        rest=$(sed 's/^[0-9]* (.*) //' /proc/$P/task/$tid/stat 2>/dev/null) || continue
        set -- $rest
        # $12=utime $13=stime (1-indexed after stripping pid+comm)
        echo "$tid $(($12+$13))"
    done
}

sample | sort -n > /tmp/cpu_a.txt
sleep "$DUR"
sample | sort -n > /tmp/cpu_b.txt
echo "=== top CPU (user+sys seconds over ${DUR}s) ==="
join /tmp/cpu_a.txt /tmp/cpu_b.txt 2>/dev/null | awk -v d="$DUR" '{x=$3-$2; if (x>0) printf "lwp=%s cpu_s=%.1f\n", $1, x/100}' | sort -t= -k3 -nr | head -n 12
echo "=== wchan of top CPU threads ==="
join /tmp/cpu_a.txt /tmp/cpu_b.txt 2>/dev/null | awk '{x=$3-$2; if (x>0) print $1, x}' | sort -k2 -nr | head -n 12 | while read t _; do
    echo -n "lwp=$t wchan="; cat /proc/$P/task/$t/wchan 2>/dev/null; echo
done
rm -f /tmp/cpu_a.txt /tmp/cpu_b.txt
echo done
