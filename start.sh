#!/bin/bash
set -e

# Mirror dashboard-ref-only's startup: create every directory hermes expects
# and seed a default config.yaml if the volume is empty. Without these,
# `hermes dashboard` endpoints that hit logs/, sessions/, cron/, etc. can fail
# with opaque errors even though no auth is actually involved.
mkdir -p /data/.hermes/cron /data/.hermes/sessions /data/.hermes/logs \
         /data/.hermes/memories /data/.hermes/skills /data/.hermes/pairing \
         /data/.hermes/hooks /data/.hermes/image_cache /data/.hermes/audio_cache \
         /data/.hermes/workspace /data/.hermes/skins /data/.hermes/plans \
         /data/.hermes/home

if [ ! -f /data/.hermes/config.yaml ] && [ -f /opt/hermes-agent/cli-config.yaml.example ]; then
  cp /opt/hermes-agent/cli-config.yaml.example /data/.hermes/config.yaml
fi

[ ! -f /data/.hermes/.env ] && touch /data/.hermes/.env

# Bootstrap OAuth tokens from env var (e.g. xAI Grok SuperGrok).
# Set HERMES_AUTH_JSON_BOOTSTRAP to the contents of a locally-generated
# ~/.hermes/auth.json. Written only once — subsequent token refreshes update
# the file in place on the persistent volume.
if [ ! -f /data/.hermes/auth.json ] && [ -n "${HERMES_AUTH_JSON_BOOTSTRAP}" ]; then
  printf '%s' "${HERMES_AUTH_JSON_BOOTSTRAP}" > /data/.hermes/auth.json
  chmod 600 /data/.hermes/auth.json
fi

# Clear stale gateway lock files left over from the previous container.
# Hermes writes two files on gateway start and does not remove them on SIGTERM:
#   gateway.pid  - PID record
#   gateway.lock - OS flock() lock used as the primary "running" guard
# Both live under /data (persistent volume) so they survive container restarts.
# gateway.pid caused "PID file race" errors; gateway.lock (added in recent hermes
# versions) causes "Gateway already running (PID X)" on every boot. During a
# Railway rolling deploy the old container can still hold the flock on gateway.lock
# while the new container tries to start, triggering the same error.
# Removing both unconditionally is safe: we are pre-exec in a fresh container and
# no hermes process from this container can be running yet.
rm -f /data/.hermes/gateway.pid /data/.hermes/gateway.lock

exec python /app/server.py
