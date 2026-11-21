# Community game results — how sharing works

YUMRAM can learn which CPU care level gives the best game frame rates on a PC (**Settings › CPU › Measure
games on this PC**). Sharing those results lets everyone with a similar CPU get good settings before they
measure anything themselves.

## For users — it is your choice

| Setting (Settings › Privacy) | Default | What it does |
|---|---|---|
| **Help everyone: share my game benchmark results** | **Off** | After "Measure games", YUMRAM shows the exact text and shares it only if you press **Share** (or automatically if you ticked "always share"). |
| **Use game results shared by other people with the same CPU** | On | Once a week YUMRAM downloads a public file from GitHub (`Community/cpu-community.json`). The request carries nothing about you. |

**Shared:** CPU model and layout (cores, threads, hybrid, cache groups), laptop or desktop, Windows build,
YUMRAM version, and the frame rates YUMRAM's own test game reached with each CPU care level.
**Never shared:** program names, files, paths, user or PC names, accounts, location, any ID that identifies you.

**How shared results are used:** only while a detected game is in front, only when at least **3** people with
your CPU (or the same CPU layout) contributed, only when one level was clearly better (≥ 10 % higher median 1 % lows),
and only until your own PC has measured games — your own measurements always win.

## For the maintainer

### Route 1 — GitHub (works today, no server)
With no server configured, **Share** opens a pre-filled "Benchmark results" issue (form
`.github/ISSUE_TEMPLATE/benchmark.yml`, label `benchmark`). The user presses Create (GitHub account needed).
Then build and publish the shared file:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Tools\Build-CommunityKnowledge.ps1 -GitHubIssues
git add Community/cpu-community.json; git commit -m "Community results update"; git push
```

### Route 2 — results server (no GitHub account needed by users)
`Server/community-worker.js` is a Cloudflare Worker (the free plan is enough):

1. Create a free Cloudflare account (only you can do this), then **Workers & Pages › Create › Worker**.
2. Paste `Server/community-worker.js`.
3. **Storage › KV › Create namespace** (e.g. `yumram-results`) and bind it to the worker as `RESULTS`.
4. Worker **Settings › Variables**: add secret `EXPORT_TOKEN` (a long random string) and variable
   `DAILY_SALT` (another random string).
5. Deploy and note the URL (e.g. `https://yumram-results.<you>.workers.dev`).
6. Ship it as the default `CommunityEndpoint` in `Config/default-config.json` in the next release.

Collect and publish:

```powershell
Invoke-WebRequest "https://<worker-url>/export?token=<EXPORT_TOKEN>" -OutFile $env:TEMP\results.json
powershell -NoProfile -ExecutionPolicy Bypass -File Tools\Build-CommunityKnowledge.ps1 -ExportFile $env:TEMP\results.json -GitHubIssues
```

The server stores only the cleaned JSON; the IP address is never stored (it is hashed with a daily salt only
to limit each address to 5 submissions a day). Every submission is checked for plausible values on the
client, on the server and again by the builder; the builder stores medians, so one odd or fake result cannot
move a CPU's advice.
