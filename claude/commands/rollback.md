Roll back a service on `$HOMESERVER` to its previous image. Usage: /rollback <service>

Expects env: `HOMESERVER` (`user@host`), and per service a compose file at `~/<service>/docker-compose.yml` on the host whose image has a `:previous` tag (pushed by the release workflow before `:latest`). Health URL defaults to `http://localhost:8000/health`; override with `HEALTH_URL`.

```bash
ssh "$HOMESERVER" "
  cd ~/<service> &&
  img=\$(docker compose config --images | head -1 | cut -d: -f1) &&
  docker compose stop &&
  docker tag \$img:previous \$img:latest &&
  docker compose up -d &&
  sleep 5 &&
  curl -s -o /dev/null -w 'health: %{http_code}\n' \${HEALTH_URL:-http://localhost:8000/health}
"
```

Present the result. If the health check fails, flag it.
