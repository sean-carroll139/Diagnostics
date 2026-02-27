#!/usr/bin/env bash
#
# Napatech Card Automated Test Script — Rev5
#
# New in Rev5:
#   • CSV logging: one line per port with timestamp, target count, actual sent, status.
#   • End-of-run summary: shows packets sent per port and whether run completed or was interrupted.
#
# Notes:
#   • Auto-detects ports using /opt/napatech3/bin/adapterinfo (no 'ntpl' dependency).
#   • Continues to the next port even if you press CTRL+C during pktgen.
#   • All logs (INFO/WARN/ERROR) go to STDERR so detection returns clean numbers only.
#
# Usage examples:
#   ./nt_auto_test_rev5.sh
#   ./nt_auto_test_rev5.sh -n 1000000000
#   ./nt_auto_test_rev5.sh -P "0,1,2,3"
#   ./nt_auto_test_rev5.sh --no-monitor
#   CSV_FILE=/path/to/results.csv ./nt_auto_test_rev5.sh
#
set -euo pipefail

# -----------------------------
# Defaults
# -----------------------------
PACKET_COUNT="${PACKET_COUNT:-100000000}"   # 100M default
USER_PORT_LIST=""
LAUNCH_MONITOR=true
SLEEP_BEFORE_SEND=2
MONITOR_GEOMETRY="${MONITOR_GEOMETRY:-120x40}"
CSV_FILE="${CSV_FILE:-./nt_results_$(date +%Y%m%d_%H%M%S).csv}"

# -----------------------------
# Tool paths
# -----------------------------
NT_BASE="/opt/napatech3/bin"
NTSTART="$NT_BASE/ntstart.sh"
MONITOR="$NT_BASE/monitoring"
PKTGEN="$NT_BASE/pktgen"
ADAPTERINFO="$NT_BASE/adapterinfo"    # correct tool (lowercase)

# -----------------------------
# Helpers (to STDERR)
# -----------------------------
log()   { echo "[INFO]  $*" >&2; }
warn()  { echo "[WARN]  $*" >&2; }
error() { echo "[ERROR] $*" >&2; exit 1; }

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") [-n PACKET_COUNT] [-P PORT_LIST] [--no-monitor]

Options:
  -n PACKET_COUNT   Number of packets per port (default: ${PACKET_COUNT})
  -P PORT_LIST      Comma-separated ports, e.g., "0,1,2,3" (overrides auto-detect)
  --no-monitor      Do not launch the monitoring UI
  -h, --help        Show this help
EOF
}

# -----------------------------
# Arg parsing
# -----------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n) PACKET_COUNT="${2:-}"; [[ -z "$PACKET_COUNT" || ! "$PACKET_COUNT" =~ ^[0-9]+$ ]] && error "Invalid -n value"; shift 2;;
    -P) USER_PORT_LIST="${2:-}"; [[ -z "$USER_PORT_LIST" ]] && error "Invalid -P value"; shift 2;;
    --no-monitor) LAUNCH_MONITOR=false; shift;;
    -h|--help) usage; exit 0;;
    *) error "Unknown option: $1";;
  esac
done

# -----------------------------
# Pre-flight checks
# -----------------------------
[[ -x "$NTSTART" ]]  || error "Missing or not executable: $NTSTART"
[[ -x "$PKTGEN"  ]]  || error "Missing or not executable: $PKTGEN"
command -v awk  >/dev/null || error "awk is required"
command -v sed  >/dev/null || error "sed is required"
command -v grep >/dev/null || error "grep is required"
if [[ ! -x "$ADAPTERINFO" ]]; then
  warn "adapterinfo tool not found at $ADAPTERINFO; auto-detect will fall back to 0 1."
fi

# -----------------------------
# CSV helpers
# -----------------------------
init_csv() {
  if [[ ! -f "$CSV_FILE" ]]; then
    echo "timestamp,host,port,packet_count_target,packets_sent,status,exit_code" > "$CSV_FILE"
    log "CSV logging to: $CSV_FILE"
  fi
}

csv_log() {
  local ts="$1" host="$2" port="$3" target="$4" sent="$5" status="$6" exit_code="$7"
  echo "${ts},${host},${port},${target},${sent},${status},${exit_code}" >> "$CSV_FILE"
}

# -----------------------------
# Start Napatech service
# -----------------------------
start_ntservice() {
  log "Starting Napatech service..."
  if "$NTSTART"; then
    log "Napatech service started successfully."
  else
    error "Failed to start Napatech service."
  fi
}

# -----------------------------
# Launch monitoring
# -----------------------------
launch_monitoring() {
  [[ "$LAUNCH_MONITOR" == true ]] || { warn "Monitoring disabled (--no-monitor)."; return 0; }
  if [[ ! -x "$MONITOR" ]]; then
    warn "Monitoring binary not found at $MONITOR; skipping monitoring."
    return 0
  fi
  if [[ "${TERM:-}" == "xterm-256color" ]]; then
    export TERM=xterm
    log "Adjusted TERM to 'xterm' for monitoring compatibility."
  fi
  if command -v xterm >/dev/null 2>&1; then
    log "Launching monitoring in a new xterm window..."
    xterm -T "Napatech Monitoring" -geometry "$MONITOR_GEOMETRY" -e "$MONITOR" &
    disown || true
    return 0
  fi
  if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
    log "Launching monitoring in a tmux split pane..."
    tmux split-window -v "$MONITOR" || warn "tmux launch failed; trying screen/background."
    return 0
  fi
  if command -v screen >/dev/null 2>&1; then
    log "Launching monitoring in a detached 'screen' session (nt-monitor)..."
    screen -dmS nt-monitor "$MONITOR" || warn "screen launch failed; running in background."
    return 0
  fi
  log "Launching monitoring in background (output -> /tmp/napatech_monitoring.log)."
  nohup "$MONITOR" > /tmp/napatech_monitoring.log 2>&1 &
  disown || true
}

# -----------------------------
# Port list helpers
# -----------------------------
normalize_port_list() { echo "$1" | sed 's/,/ /g' | awk '{for(i=1;i<=NF;i++){ if($i ~ /^[0-9]+$/) printf "%s ", $i}}'; }
dedupe_and_sort()      { tr ' ' '\n' | awk 'NF' | sort -n | uniq | paste -sd ' ' -; }

# -----------------------------
# Port detection (adapterinfo only)
# -----------------------------
detect_ports() {
  local out detected="" count="" rmin="" rmax=""
  if [[ -x "$ADAPTERINFO" ]]; then
    out="$("$ADAPTERINFO" 2>/dev/null || true)"
    count="$(echo "$out" | grep -m1 -E '^[[:space:]]*Ports:[[:space:]]*[0-9]+' | sed -E 's/^.*Ports:[[:space:]]*([0-9]+).*$/\1/' || true)"
    if [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]]; then
      for ((i=0;i<count;i++)); do detected+="${i} "; done
      echo "$detected"; return 0
    fi
    rmin="$(echo "$out" | grep -m1 -E '^[[:space:]]*Port[[:space:]]*range:[[:space:]]*[0-9]+[[:space:]]*-[[:space:]]*[0-9]+' | sed -E 's/^.*range:[[:space:]]*([0-9]+)[[:space:]]*-[[:space:]]*([0-9]+).*$/\1/' || true)"
    rmax="$(echo "$out" | grep -m1 -E '^[[:space:]]*Port[[:space:]]*range:[[:space:]]*[0-9]+[[:space:]]*-[[:space:]]*[0-9]+' | sed -E 's/^.*range:[[:space:]]*([0-9]+)[[:space:]]*-[[:space:]]*([0-9]+).*$/\2/' || true)"
    if [[ "$rmin" =~ ^[0-9]+$ && "$rmax" =~ ^[0-9]+$ && "$rmax" -ge "$rmin" ]]; then
      for ((i=rmin;i<=rmax;i++)); do detected+="${i} "; done
      echo "$detected"; return 0
    fi
    detected="$(echo "$out" | grep -Eo 'Port #[0-9]+' | grep -Eo '[0-9]+' | paste -sd ' ' -)"
    if [[ -n "$detected" ]]; then echo "$detected"; return 0; fi
  fi
  echo "0 1"
}

# -----------------------------
# Parse pktgen output to get final 'sent' count for the port
# -----------------------------
extract_sent_count() {
  local logfile="$1" port="$2" line="" num=""
  # Preferred: "Sent X packets in total onto port P"
  line="$(grep -E "Sent[[:space:]][0-9]+[[:space:]]+packets[[:space:]]+in[[:space:]]+total[[:space:]]+onto[[:space:]]+port[[:space:]]+${port}\b" "$logfile" | tail -n1 || true)"
  if [[ -n "$line" ]]; then
    num="$(echo "$line" | grep -Eo '[0-9]+' | head -n1)"
    echo "${num:-0}"
    return 0
  fi
  # Fallback: last "Sent X packets so far." or "Cnt X packets so far."
  line="$(grep -E "Sent[[:space:]][0-9]+[[:space:]]+packets[[:space:]]+so[[:space:]]+far\.|Cnt[[:space:]][0-9]+[[:space:]]+packets[[:space:]]+so[[:space:]]+far\." "$logfile" | tail -n1 || true)"
  if [[ -n "$line" ]]; then
    num="$(echo "$line" | grep -Eo '[0-9]+' | head -n1)"
    echo "${num:-0}"
    return 0
  fi
  echo "0"
}

# -----------------------------
# Run pktgen for ports, capture logs, write CSV, collect summary
# -----------------------------
run_pktgen_with_logging() {
  local -n ports_ref=$1
  local -a COUNTS=()
  local -a STATUSES=()
  local host="$(hostname -s || echo host)"
  local ts=""

  log "Beginning traffic generation: ${PACKET_COUNT} packets per port."
  init_csv

  for p in "${ports_ref[@]}"; do
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    log "Sending ${PACKET_COUNT} packets on port ${p}..."

    # Per-port log file in /tmp (you can change if you want)
    local port_log="/tmp/pktgen_port_${p}_$(date +%s).log"

    # Run pktgen and tee output; do not exit on ctrl+c (non-zero); we handle status.
    set +e
    if command -v stdbuf >/dev/null 2>&1; then
      "$PKTGEN" -p "$p" -n "$PACKET_COUNT" | stdbuf -oL tee "$port_log"
    else
      "$PKTGEN" -p "$p" -n "$PACKET_COUNT" | tee "$port_log"
    fi
    local rc=$?
    set -e

    # Determine whether it completed or was interrupted, and how many were sent.
    local sent="$(extract_sent_count "$port_log" "$p")"
    local status="completed"
    if [[ $rc -ne 0 ]]; then
      status="interrupted"
      warn "Port ${p}: pktgen interrupted (exit $rc)."
    else
      log "Port ${p}: pktgen completed."
    fi

    COUNTS+=("$sent")
    STATUSES+=("$status")

    # Append CSV
    csv_log "$ts" "$host" "$p" "$PACKET_COUNT" "$sent" "$status" "$rc"
  done

  # Print summary
  echo -e "\n========== Summary ==========" >&2
  for i in "${!ports_ref[@]}"; do
    echo "Port ${ports_ref[$i]}  ->  ${COUNTS[$i]} packets  (${STATUSES[$i]})" >&2
  done
  echo "CSV file: $CSV_FILE" >&2
}

# -----------------------------
# Main
# -----------------------------
main() {
  start_ntservice
  launch_monitoring
  sleep "$SLEEP_BEFORE_SEND"

  local ports_space=""
  if [[ -n "$USER_PORT_LIST" ]]; then
    ports_space="$(normalize_port_list "$USER_PORT_LIST")"
    [[ -z "$ports_space" ]] && error "Provided -P PORT_LIST is invalid."
    log "Using user-provided port list: $ports_space"
  else
    ports_space="$(detect_ports)"
  fi

  # Build array
  read -r -a PORTS <<<"$(echo "$ports_space" | dedupe_and_sort)"
  [[ ${#PORTS[@]} -gt 0 ]] || error "No ports detected after normalization."
  log "Final port list: ${PORTS[*]}"

  run_pktgen_with_logging PORTS

  log "Observe the monitoring window for:"
  echo "  - Frame Drops (should remain 0)"
  echo "  - Host Buffer Overflows (0)"
  echo "  - PCIe Drops (0)"
  echo "  - Link status = UP"
  echo "  - Expected packet counts"
  log "Done."
}

main "$@"