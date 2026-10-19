#!/usr/bin/env bash
# enumerate-runs.sh <periodic|presubmit> <job-name>
#
# periodic:   prints one build ID per line, descending (most recent first).
# presubmit:  prints "<build_id> <pr_number>" per line, descending.
set -euo pipefail

MODE="${1:?Usage: enumerate-runs.sh <periodic|presubmit> <job-name>}"
JOB="${2:?Usage: enumerate-runs.sh <periodic|presubmit> <job-name>}"
BUCKET="test-platform-results"
API="https://storage.googleapis.com/storage/v1/b/${BUCKET}/o"

fetch_all_pages() {
  local url_base="$1"
  local jq_filter="$2"
  local page_token=""
  local results=()
  local resp
  while :; do
    local url="${url_base}"
    if [[ -n "$page_token" ]]; then
      url="${url}&pageToken=${page_token}"
    fi
    resp=$(curl -sf --connect-timeout 10 --max-time 30 "$url")
    while IFS= read -r line; do
      [[ -n "$line" ]] && results+=("$line")
    done < <(echo "$resp" | jq -r "$jq_filter")
    page_token=$(echo "$resp" | jq -r '.nextPageToken // empty')
    [[ -z "$page_token" ]] && break
  done
  printf '%s\n' "${results[@]}"
}

case "$MODE" in
  periodic)
    url="${API}?prefix=logs/${JOB}/&delimiter=/&fields=prefixes,nextPageToken"
    filter='.prefixes[]? | capture("logs/'"${JOB}"'/(?<id>[0-9]+)/").id'
    fetch_all_pages "$url" "$filter" | sort -rn
    ;;
  presubmit)
    url="${API}?prefix=pr-logs/directory/${JOB}/&fields=items(name),nextPageToken"
    filter='.items[]? | .name | capture("/(?<id>[0-9]+)\\.txt$").id'
    ids=$(fetch_all_pages "$url" "$filter" | sort -rn)
    for id in $ids; do
      ptr=$(curl -sf --connect-timeout 10 --max-time 15 \
        "https://storage.googleapis.com/${BUCKET}/pr-logs/directory/${JOB}/${id}.txt")
      pr=$(echo "$ptr" | sed -E "s#.*/([0-9]+)/${JOB}/.*#\\1#")
      echo "${id} ${pr}"
    done
    ;;
  *)
    echo "Usage: $0 <periodic|presubmit> <job-name>" >&2
    exit 1
    ;;
esac
