# Reusing this agent container in another repo

This directory packages a reusable dev-container that gives a repo:

- **Omnigent host auto-registration** — the container registers itself as a
  host named after the repo, so Web-UI / `omni` agent sessions land here.
- **opencode config injection** — your host MCP servers + model + variant
  reach every opencode session, even though omnigent hides your global config.
- The usual tooling (Rust, Flutter, opencode/claude/happy CLIs, docker socket).

The two mechanisms above are **repo-agnostic** — they read from the host global
opencode config and derive the host name from the working dir. The only things
that change per repo are a mount path and a couple of names.

---

## TL;DR — apply to a new repo in 5 steps

```bash
# 1. Copy this agent/ dir into the new repo
cp -r agent/ /path/to/newrepo/agent/

# 2. cd there, then do a global rename: icp-cc -> <newrepo>
cd /path/to/newrepo
NEW=myproj                                   # your repo's dirname
grep -rl 'icp-cc' agent/ | xargs sed -i "s/icp-cc/$NEW/g"

# 3. Make sure the generated config is never committed
printf '\n.opencode/\n' >> .gitignore

# 4. Build the image
docker compose -f agent/docker-compose.yml build

# 5. Verify (see "Verification" below)
```

That's it. After step 2 every `/code/icp-cc`, the `icp-cc-agent` image, and the
`icp-cc-network` become `/code/$NEW`, `$NEW-agent`, `$NEW-network`.

> The rename is safe because `icp-cc` is a unique token in these files — it
> only appears as the repo mount path, image name, and network name.

---

## What each piece does (so you can adapt, not just copy)

### 1. Omnigent registration — `entrypoint.sh` lines ~42-95

On every container **start** (not `exec`), it:
1. Derives a host name from `$(basename "$(pwd)")` (= the repo dir). Override
   with `OMNIGENT_HOST_NAME`.
2. Seeds a **stable** `host_id` (sha256 of the name) into `~/.omnigent/config.yaml`
   so an ephemeral `--rm` container reconnects as the *same* host.
3. Launches `omnigent host --server "$OMNIGENT_SERVER_URL" --non-interactive`
   in the background, then does a 3s grace check — if the daemon died (auth
   refused / binary missing), it prints the failure to stderr.

**Nothing here is repo-specific** — it's all driven by the cwd / env vars.
Disable with `OMNIGENT_AUTO_REGISTER=0`. Point at another server with
`OMNIGENT_SERVER_URL`.

### 2. opencode config injection — `entrypoint.sh` lines ~97-140

This is the fix for "omnigent-launched opencode has none of my MCP servers".
Omnigent launches each opencode session with a private per-session
`XDG_CONFIG_HOME` and synthesizes a fresh `opencode.json` there — it only merges
your `provider` entries, **never your `mcp`** servers.

But opencode **merges a project `opencode.json` from the cwd** on top of that
synthesized config. So the entrypoint generates `/code/<repo>/.opencode/opencode.json`
**from your host global config** (`~/.config/opencode/opencode.json`) containing:
`model` + the full `mcp` block + `agent.build.variant`. This reaches **every**
opencode session (`omni opencode`, `omni run`, or Web UI).

- **No committed secret**: the file is derived from the host config at runtime
  and `.opencode/` is gitignored (step 3 above).
- Disable with `OPENCODE_INJECT_PROJECT_CONFIG=0`.
- Change the default variant with `OPENCODE_MODEL_VARIANT` (default `max`).

### 3. `.gitignore` — must contain `.opencode/`

Because the generated `.opencode/opencode.json` contains your live API tokens
(copied from the host global config). Verify:

```bash
git check-ignore -v .opencode/opencode.json   # should print the .gitignore rule
```

---

## Repository-specific tokens

After copying, the only literal that encodes "this repo" is `icp-cc`. It maps to:

| Where | `icp-cc` value | Becomes |
|-------|----------------|---------|
| `docker-compose.yml` volume | `/code/icp-cc` mount + working_dir | `/code/$NEW` |
| `docker-compose.yml` image | `icp-cc-agent:latest` | `$NEW-agent:latest` |
| `docker-compose.yml` network | `icp-cc-network` | `$NEW-network` |
| `entrypoint.sh` | `/code/icp-cc` paths (target, .opencode, etc.) | `/code/$NEW` |
| `run-container.sh` | flock lock dir, project name | `$NEW` |
| `DOCKER_README.md` | examples | `$NEW` |

The global `sed` in the TL;DR handles all of these.

> **Dockerfile note (important):** the `UV_TOOL_DIR` / `UV_TOOL_BIN_DIR` /
> `UV_PYTHON_INSTALL_DIR` ENVs force omnigent's venv, shims, **and Python
> interpreter** under `/home/ubuntu/.local/`. Do **not** change these to a
> `.cache` path — the `home-cache` named volume masks `.cache`, which silently
> breaks the omnigent binaries (`setsid: ... No such file or directory`).

---

## Customization knobs (env vars in `docker-compose.yml`)

| Var | Default | Effect |
|-----|---------|--------|
| `OMNIGENT_SERVER_URL` | `http://192.168.0.2:6767` | Omnigent server to register with |
| `OMNIGENT_AUTO_REGISTER` | `1` | `0` skips host registration entirely |
| `OMNIGENT_HOST_NAME` | repo dirname | Override the host name shown on the server |
| `OPENCODE_INJECT_PROJECT_CONFIG` | `1` | `0` skips `.opencode/opencode.json` generation |
| `OPENCODE_MODEL_VARIANT` | `max` | Default model variant for the `build` agent |
| `OPENCODE_CONFIG_CONTENT` | `{"permission":"allow"}` | Container-direct opencode only (omnigent strips this) |

---

## Verification

After building + starting a container (`run-container.sh bash` or
`docker compose run agent bash`):

```bash
# 1. Host registered + online (takes ~15s for omnigent to import its deps)
cat ~/.omnigent/logs/host-register.log      # expect "✓ Connected as '<repo>'"
# then on the server host:
curl -s http://192.168.0.2:6767/v1/hosts | grep <repo>   # status: online

# 2. opencode config was injected
cat /code/<repo>/.opencode/opencode.json    # model + mcp + variant:max

# 3. MCP servers reach an omnigent-style session
#    (opencode merges the cwd project config over the synthesized one)
XDG_CONFIG_HOME=$(mktemp -d) opencode debug config 2>/dev/null | grep -A20 '"mcp"'
#    expect: plasmate, lightpanda, web-search-prime, web-reader, zread, zai-vision
```

---

## Prerequisites on the host (one-time)

These are what make the injection work; they live on the **host**, not in any
repo, so you set them up once:

1. **Host opencode global config** at `~/.config/opencode/opencode.json` with
   your `model`, `provider`, and `mcp` servers. This is the single source of
   truth the entrypoint derives from.
2. **omnigent auth**, if your server requires it: run `omnigent login`
   interactively inside a container once — credentials persist in the
   `omnigent-state` volume across `--rm` runs.
3. The host dirs mounted in `docker-compose.yml` (`~/.config/opencode`,
   `~/.opencode`, `~/.local/share/opencode`, `~/.claude`, `~/.ssh/claude-code`,
   `~/Android`).
