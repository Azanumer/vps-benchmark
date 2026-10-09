# VPS Benchmark

One-script VPS benchmark that writes a Markdown report. No dependencies beyond what a typical Ubuntu VPS already has (`curl`, `dd`, `awk`); `sysbench` is used automatically when present.

## What it measures

- **System** — OS, kernel, CPU model, cores, RAM, uptime
- **CPU** — `sysbench cpu` events/sec, or OpenSSL AES-128-CBC throughput, or a bash-loop fallback
- **Disk** — 1GB sequential write/read with `fdatasync` (real device throughput, not page cache)
- **Network** — 100MB download from Cloudflare and OVH speed-test endpoints

## Usage

```bash
chmod +x benchmark.sh
./benchmark.sh                  # full test, writes BENCHMARK.md
./benchmark.sh --quick           # skip the 1GB disk test
./benchmark.sh --output my.md    # custom report path
```

Run it before buying a VPS (most providers have a trial/hourly option), after migrating, and after tuning — then diff the reports.

MIT licensed.
