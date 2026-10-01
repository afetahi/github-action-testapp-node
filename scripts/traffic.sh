#!/usr/bin/env bash
# Generates traffic against the app so the SRE agent has telemetry to analyze.
#
# Usage: bash scripts/traffic.sh <base-url> [mode] [duration-seconds]
#   modes: normal (default), errors, slow, cpu, memory, mixed
#   Fault modes need the app setting CHAOS_ENABLED=true (otherwise those calls return 404).
#
# Example:
#   bash scripts/traffic.sh https://<app>-staging.azurewebsites.net errors 300
set -uo pipefail

BASE="${1:?usage: bash scripts/traffic.sh <base-url> [normal|errors|slow|cpu|memory|mixed] [duration-seconds]}"
BASE="${BASE%/}"
MODE="${2:-normal}"
DURATION="${3:-300}"

normal_paths=(/ /api/health /api/info /api/info)
case "$MODE" in
  normal|cpu|memory) paths=("${normal_paths[@]}") ;;
  errors) paths=("${normal_paths[@]}" /api/error /api/error) ;;
  slow)   paths=("${normal_paths[@]}" "/api/slow?ms=4000" "/api/slow?ms=8000") ;;
  mixed)  paths=("${normal_paths[@]}" /api/error "/api/slow?ms=5000") ;;
  *) echo "Unknown mode: $MODE (use normal, errors, slow, cpu, memory or mixed)" >&2; exit 2 ;;
esac

declare -A counts=()

hit() {
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$BASE$1") || code="ERR"
  counts[$code]=$(( ${counts[$code]:-0} + 1 ))
  printf '%s  %-4s %s\n' "$(date +%H:%M:%S)" "$code" "$1"
}

summary() {
  if [[ "$MODE" == "memory" ]]; then
    curl -s -o /dev/null --max-time 20 "$BASE/api/memory/release" && echo "Released held memory."
  fi
  echo
  echo "Summary: mode=$MODE, target=$BASE"
  for code in "${!counts[@]}"; do
    echo "  HTTP $code: ${counts[$code]}"
  done
}
trap summary EXIT

echo "Sending '$MODE' traffic to $BASE for ${DURATION}s (Ctrl+C to stop)"
end=$((SECONDS + DURATION))
next_fault=$SECONDS
while (( SECONDS < end )); do
  if (( SECONDS >= next_fault )); then
    case "$MODE" in
      cpu)    hit "/api/cpu?seconds=25"; next_fault=$((SECONDS + 30)) ;;
      memory) hit "/api/memory?mb=40";   next_fault=$((SECONDS + 30)) ;;
      *)      next_fault=$end ;;
    esac
  fi
  hit "${paths[RANDOM % ${#paths[@]}]}"
  sleep 1
done
