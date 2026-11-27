Run a full healthcheck on the home server at `$HOMESERVER` (`user@host`).

Run ALL of the following checks over SSH and present results in a clean summary. Run independent checks in parallel where possible.

## Connectivity
- Ping the server (2 packets)

## System
- `uptime` (uptime + load average)
- `df -h /` (disk usage)
- `free -h` (memory usage)

## Docker
- `docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"` (all containers and status)
- `docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"` (resource usage)
- `docker ps -a --format "table {{.Names}}\t{{.Status}}"` (check for restarted/exited containers)

## App-level
- For each URL in `$HC_URLS` (space-separated), `curl -s -o /dev/null -w "%{http_code}"` it

## Summary
Present results as a brief status table:
| Check | Status |
At the end, flag anything that looks unhealthy (high load, low disk, containers down, non-200 responses).
