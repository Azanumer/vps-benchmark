#!/usr/bin/env bash
#
# benchmark.sh — quick VPS benchmark with a Markdown report.
#
# Measures CPU, disk I/O and network throughput, then writes BENCHMARK.md
# next to this script. Safe: creates no files outside /tmp and the report.
#
# Usage: ./benchmark.sh [--quick] [--output FILE]
#   --quick   skip the 1GB disk write test (faster, less wear)
#   --output  report path (default: BENCHMARK.md)
#
set -euo pipefail

QUICK=0
OUT="BENCHMARK.md"

while [ $# -gt 0 ]; do
    case "$1" in
        --quick)  QUICK=1; shift ;;
        --output) OUT="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

say() { printf '%s\n' "$*"; }

# --- System info -----------------------------------------------------------
HOSTNAME_FQDN="$(hostname -f 2>/dev/null || hostname)"
OS="$( (grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"') || uname -s)"
KERNEL="$(uname -r)"
ARCH="$(uname -m)"
CPU_MODEL="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ *//' || echo 'unknown')"
CPU_CORES="$(nproc 2>/dev/null || echo '?')"
RAM_MB="$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo '?')"
UPTIME="$(uptime -p 2>/dev/null || uptime)"

# --- CPU benchmark ----------------------------------------------------------
# Prefer sysbench; fall back to a pure-bash loop timing (deterministic-ish).
say "Running CPU test..."
if command -v sysbench >/dev/null 2>&1; then
    CPU_RESULT="$(sysbench cpu --cpu-max-prime=20000 run 2>/dev/null \
        | grep -E 'events per second' | awk '{print $4}')"
    CPU_METHOD="sysbench cpu (prime=20000): ${CPU_RESULT} events/sec"
elif command -v openssl >/dev/null 2>&1; then
    # openssl speed is a rough but widely available CPU proxy.
    AES="$(openssl speed -elapsed -evp aes-128-cbc 2>/dev/null \
        | awk '/^aes-128-cbc/ {for(i=1;i<=NF;i++) if ($i ~ /^[0-9.]+k$/) {gsub(/k/,"",$i); print $i"kB/s"; exit}}')"
    CPU_METHOD="openssl aes-128-cbc: ${AES:-n/a}"
else
    START="$(date +%s%N)"
    I=0; while [ "$I" -lt 200000 ]; do I=$((I+1)); done
    MS=$(( ($(date +%s%N) - START) / 1000000 ))
    CPU_METHOD="bash loop (200k iterations): ${MS} ms"
fi

# --- Disk benchmark ----------------------------------------------------------
say "Running disk test..."
DISK_LINE="skipped (--quick)"
if [ "$QUICK" -eq 0 ]; then
    TMPF="$(mktemp /tmp/bench.XXXXXX)"
    # conv=fdatasync so we measure real device throughput, not page cache.
    DD_OUT="$(dd if=/dev/zero of="$TMPF" bs=1M count=1024 oflag=direct conv=fdatasync 2>&1 || \
              dd if=/dev/zero of="$TMPF" bs=1M count=1024 conv=fdatasync 2>&1)"
    WRITE="$(printf '%s' "$DD_OUT" | grep -oE '[0-9.]+ [GMK]B/s' | tail -1)"
    READ="$(dd if="$TMPF" of=/dev/null bs=1M iflag=direct 2>&1 \
        | grep -oE '[0-9.]+ [GMK]B/s' | tail -1)"
    rm -f "$TMPF"
    DISK_LINE="sequential write ${WRITE:-n/a}, sequential read ${READ:-n/a} (1GB, fdatasync)"
fi

# --- Network benchmark --------------------------------------------------------
say "Running network test..."
# Download a 100MB test file from two CDNs, take the better median-ish result.
NET_RESULTS=""
for URL in "https://speed.cloudflare.com/__down?bytes=104857600" \
           "https://proof.ovh.net/files/100Mb.dat"; do
    if SPEED="$(curl -s -o /dev/null -w '%{speed_download}' --max-time 25 "$URL" 2>/dev/null)"; then
        MBPS="$(awk -v s="$SPEED" 'BEGIN {printf "%.1f", s*8/1000000}')"
        HOST="$(printf '%s' "$URL" | cut -d/ -f3)"
        NET_RESULTS="${NET_RESULTS}- ${HOST}: ${MBPS} Mbit/s (100MB download)\n"
    fi
done
[ -z "$NET_RESULTS" ] && NET_RESULTS="unavailable (no network or curl blocked)"

# --- Report ---------------------------------------------------------------------
NOW="$(date -u '+%Y-%m-%d %H:%M UTC')"
{
    say "# VPS Benchmark"
    say ""
    say "_Generated ${NOW} on ${HOSTNAME_FQDN}_"
    say ""
    say "## System"
    say ""
    say "| | |"
    say "|---|---|"
    say "| OS | ${OS} |"
    say "| Kernel | ${KERNEL} |"
    say "| Arch | ${ARCH} |"
    say "| CPU | ${CPU_MODEL} |"
    say "| Cores | ${CPU_CORES} |"
    say "| RAM | ${RAM_MB} MB |"
    say "| Uptime | ${UPTIME} |"
    say ""
    say "## CPU"
    say ""
    say "${CPU_METHOD}"
    say ""
    say "## Disk"
    say ""
    say "${DISK_LINE}"
    say ""
    say "## Network"
    say ""
    printf '%b' "$NET_RESULTS"
} > "$OUT"

say ""
say "Report written to ${OUT}"
