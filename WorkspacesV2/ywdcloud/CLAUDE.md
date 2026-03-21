# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OCI (Oracle Cloud Infrastructure) resource lifecycle automation toolkit written in Bash. Discovers, lists, starts, and stops cloud resources (VMs, databases, Autonomous DBs, GoldenGate) across multiple regions with state persistence.

## Running the Tool

```bash
./main.sh list [vm|db|adb|gg|all] [--region <r>|--regions r1,r2] [--compartment-id <ocid>]
./main.sh start [vm|db|adb|gg|all]
./main.sh stop [vm|db|adb|gg|all]
./main.sh compartments [--tenancy-id <ocid>]
```

No build step required. Dependencies: `oci` CLI and `jq` must be in PATH.

## Architecture

**Entry point:** `main.sh` — parses CLI args and routes to resource-type handlers.

**`lib/` modules** (sourced by `main.sh`):
- `common.sh` — `log()`, `retry()`, `require_env()`, `print_table()` utilities
- `state.sh` — JSON state persistence (`init_state()` / `append_state()` / `finalize_state()`)
- `compute.sh` — OCI Compute VM operations
- `db.sh` — OCI Database System operations
- `adb.sh` — OCI Autonomous Database operations
- `gg.sh` — OCI GoldenGate deployment operations

**State flow:** All resource modules follow the same pattern — query OCI CLI → parse JSON with `jq` → format tabular output → append to `state/state.json`.

**Configuration:** `.env` sets default `REGIONS`, `COMPARTMENT_ID` variants, `MAX_RETRIES`, `RETRY_DELAY`, and `LOG_FILE`. OCI credentials are in `.oci/config` with named profiles (`SEOUL`, `mobisexacc`, `DXOCIAGENT`).

## State-based workflow

`list` → builds `state/state.json` → `start`/`stop` reads that file.
Always run `./main.sh list` before `start`/`stop` to refresh state.

`start`/`stop` skip resources already in the target state (e.g., RUNNING VMs when starting). DB System start/stop operates at the DB Node level via `oci db node action`.

## Known Issues

- No test infrastructure exists on this branch (`dev_oci/unittest`).
