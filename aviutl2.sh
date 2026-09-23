#!/bin/bash
# Launch AviUtl2 with CPU affinity tuned for reliable playback stop.
#
# Background (verified 2026-09-21): on a 12-core machine, unrestricted
# scheduling makes Space-stop unreliable (up to 29s delay, often never).
# Restricting to 4 cores gives consistent <=1s stops (5/5 trials).
# The toggle path submits a job and waits on workers; with cores to spare
# the thread interleaving apparently never aligns, while constrained
# scheduling aligns it reliably.
#
# Usage: ./aviutl2.sh [args...]
#   TASKSET_CPUS=8-11 ./aviutl2.sh   # try a different core set
#
# IMPORTANT: always use this (or the full staging path) to launch.
# `wine` on PATH is the distro's Wine 10.0 and must NOT be used.
set -euo pipefail

TASKSET_CPUS="${TASKSET_CPUS:-0-3}"
exec taskset -c "$TASKSET_CPUS" /opt/wine-staging/bin/wine /home/p-yoko/App/Aviutl2/aviutl2.exe "$@"
