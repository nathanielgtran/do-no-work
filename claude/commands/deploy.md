Deploy a service. Usage: /deploy [service] [version]

Service is a repo under `~/Github/`. Version is optional (defaults to next patch bump). Deploys go to `$HOMESERVER` (`user@host`).

## Steps

1. **Determine the service and version**
   - If no service specified, use the current repo
   - If no version specified, check the latest git tag and bump the patch version
   - Show the user: "Deploying [service] v[version]" and confirm

2. **Pre-deploy checks**
   - Ensure you're on the `main` branch and it's up to date with origin
   - Run the repo's test and lint commands (see its README or REPOS.md)
   - Check for uncommitted changes -- warn if any

3. **Create the release**
   - Create and push the git tag: `git tag v[version] && git push origin v[version]`
   - Create the GitHub release: `gh release create v[version] --title "v[version]" --generate-notes`
   - This triggers the release workflow automatically

4. **Monitor the deploy**
   - Watch the GitHub Actions workflow: `gh run list --workflow=release.yml --limit=1`
   - Poll until complete (check every 30 seconds, max 10 minutes)
   - Report: which jobs passed/failed

5. **Verify**
   - SSH to `$HOMESERVER` and check the service's container is running the new image tag:
     `ssh "$HOMESERVER" "docker ps --format '{{.Names}} {{.Image}} {{.Status}}'"`
   - Hit the health endpoint to confirm the service is up
   - Purge Cloudflare cache if the service has a frontend component

6. **Report**
   - Summary: version deployed, all checks passed/failed, container status

If any step fails, stop and report the failure. Do not continue blindly.
