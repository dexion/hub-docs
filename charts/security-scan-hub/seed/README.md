# seed/ — vendored demo-seed scripts

These files are **vendored** (copied) from the `dd-clone` (SecurityScanHub) repo and
are the data source for the demo-reseed CronJob (`demoReseed.enabled=true`).

Source of truth (keep in sync — do NOT edit here, edit upstream then re-copy):

| File(s)                     | Upstream path in `dd-clone`        |
|-----------------------------|------------------------------------|
| `seed_demo.py`, `_seed_*.py`| `scripts/`                         |
| `full-sarif.sarif`          | `demo/seed-assets/full-sarif.sarif`|

## How they are used

The `demo-reseed-configmap.yaml` template bakes every file in this directory into a
ConfigMap via `(.Files.Glob "seed/*").AsConfig`, mounted at `/seed` in the CronJob
`seed` container. The CronJob runs:

```
python /seed/seed_demo.py --db-url "$DB_URL" --clean --scale <scale>
```

`seed_demo.py`:
- `--clean` truncates all tables, then reseeds users / projects / scope / findings /
  social data at the requested `--scale` (small | medium | large).
- Phase 8 uploads `full-sarif.sarif` (read from `/seed/full-sarif.sarif`, i.e. its own
  dir) to the backend (`BACKEND_URL`, default `http://hub-backend:8082`) using the
  seeded `gitlab-ci-scanner` SA API key, to showcase a rich SARIF report.

After seeding, the CronJob PATCHes the backend Deployment's pod template
(`kubectl.kubernetes.io/restartedAt`) to trigger a rollout so Casbin policies and
in-memory state reload against the fresh dataset.

## Keeping in sync

When the upstream scripts change, re-copy from `dd-clone`:

```sh
SRC=/path/to/dd-clone
DST=charts/security-scan-hub/seed
cp "$SRC"/scripts/seed_demo.py "$SRC"/scripts/_seed_*.py "$DST"/
cp "$SRC"/demo/seed-assets/full-sarif.sarif "$DST"/
```
