#!/bin/bash

# ============================================================
# Generic Parallel HTTP Load Test Script
# ============================================================

# ============================================================
# USAGE
# ============================================================
usage() {
    echo ""
    echo -e "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -m, --method       HTTP method: GET, POST, PUT, DELETE, PATCH  (default: GET)"
    echo "  -u, --url          Request URL (required)"
    echo "                     Use {{INDEX}} as placeholder for the iteration index (0-based)"
    echo "                     Use {{DATE}} as placeholder for an auto-incremented date"
    echo "  -n, --number       Number of parallel requests                  (default: 10)"
    echo "  -H, --header       Header in 'Key: Value' format, repeatable"
    echo "  -d, --data         Request body (for POST/PUT/PATCH)"
    echo "  -f, --data-file    Path to file to use as request body"
    echo "  -D, --base-date    Base date for {{DATE}} placeholder            (default: today)"
    echo "  -t, --timeout      Request timeout in seconds                   (default: 30)"
    echo "  -o, --output       Save full response bodies to this directory"
    echo "  -v, --verbose      Print each request URL before firing"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo ""
    echo "  # Simple GET - same URL repeated 5 times"
    echo "  $0 -m GET -u 'https://api.example.com/items' -n 5 \\"
    echo "     -H 'Authorization: Bearer TOKEN' \\"
    echo "     -H 'Accept: application/json'"
    echo ""
    echo "  # GET with auto-incrementing date placeholder"
    echo "  $0 -m GET -u 'https://api.example.com/items?date={{DATE}}' -n 10 \\"
    echo "     -D 2026-03-16 \\"
    echo "     -H 'Authorization: Bearer TOKEN'"
    echo ""
    echo "  # GET with index placeholder"
    echo "  $0 -m GET -u 'https://api.example.com/items/{{INDEX}}' -n 10 \\"
    echo "     -H 'Authorization: Bearer TOKEN'"
    echo ""
    echo "  # POST with inline body"
    echo "  $0 -m POST -u 'https://api.example.com/items' -n 5 \\"
    echo "     -H 'Authorization: Bearer TOKEN' \\"
    echo "     -H 'Content-Type: application/json' \\"
    echo "     -d '{\"name\": \"test\"}'"
    echo ""
    echo "  # POST with body from file"
    echo "  $0 -m POST -u 'https://api.example.com/items' -n 5 \\"
    echo "     -H 'Authorization: Bearer TOKEN' \\"
    echo "     -f ./body.json"
    echo ""
    exit 0
}

# ============================================================
# Colour helpers
# ============================================================
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ============================================================
# Defaults
# ============================================================
METHOD="GET"
URL=""
NUM_REQUESTS=10
HEADERS=()
BODY=""
BODY_FILE=""
BASE_DATE=$(date +%Y-%m-%d)
TIMEOUT=30
OUTPUT_DIR=""
VERBOSE=false

# ============================================================
# Parse arguments
# ============================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--method)
            METHOD=$(echo "$2" | tr '[:lower:]' '[:upper:]')
            shift 2 ;;
        -u|--url)
            URL="$2"
            shift 2 ;;
        -n|--number)
            NUM_REQUESTS="$2"
            shift 2 ;;
        -H|--header)
            HEADERS+=("$2")
            shift 2 ;;
        -d|--data)
            BODY="$2"
            shift 2 ;;
        -f|--data-file)
            BODY_FILE="$2"
            shift 2 ;;
        -D|--base-date)
            BASE_DATE="$2"
            shift 2 ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2 ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2 ;;
        -v|--verbose)
            VERBOSE=true
            shift ;;
        -h|--help)
            usage ;;
        *)
            echo -e "${RED}ERROR: Unknown option '$1'${RESET}"
            echo "Run '$0 --help' for usage."
            exit 1 ;;
    esac
done

# ============================================================
# Validate inputs
# ============================================================
if [[ -z "$URL" ]]; then
    echo -e "${RED}ERROR: --url is required.${RESET}"
    echo "Run '$0 --help' for usage."
    exit 1
fi

if ! [[ "$NUM_REQUESTS" =~ ^[0-9]+$ ]] || [[ "$NUM_REQUESTS" -lt 1 ]]; then
    echo -e "${RED}ERROR: --number must be a positive integer (got: '${NUM_REQUESTS}').${RESET}"
    exit 1
fi

if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$TIMEOUT" -lt 1 ]]; then
    echo -e "${RED}ERROR: --timeout must be a positive integer (got: '${TIMEOUT}').${RESET}"
    exit 1
fi

case "$METHOD" in
    GET|POST|PUT|DELETE|PATCH) ;;
    *)
        echo -e "${RED}ERROR: Unsupported method '${METHOD}'. Use GET, POST, PUT, DELETE or PATCH.${RESET}"
        exit 1 ;;
esac

if [[ -n "$BODY_FILE" && ! -f "$BODY_FILE" ]]; then
    echo -e "${RED}ERROR: --data-file '${BODY_FILE}' does not exist.${RESET}"
    exit 1
fi

if [[ -n "$BODY_FILE" && -n "$BODY" ]]; then
    echo -e "${RED}ERROR: Use either --data or --data-file, not both.${RESET}"
    exit 1
fi

if [[ -n "$OUTPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR" || {
        echo -e "${RED}ERROR: Cannot create output directory '${OUTPUT_DIR}'.${RESET}"
        exit 1
    }
fi

# ============================================================
# Temp directory
# ============================================================
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# ============================================================
# Cross-platform millisecond timestamp
# ============================================================
get_ms() {
    if command -v python3 &>/dev/null; then
        python3 -c "import time; print(int(time.time() * 1000))"
    elif command -v python &>/dev/null; then
        python -c "import time; print(int(time.time() * 1000))"
    else
        echo $(( $(date +%s) * 1000 ))
    fi
}

# ============================================================
# Cross-platform date increment
# ============================================================
increment_date() {
    local base_date="$1"
    local days="$2"
    if date --version &>/dev/null 2>&1; then
        date -d "${base_date} + ${days} days" +%Y-%m-%d
    else
        date -j -v+${days}d -f "%Y-%m-%d" "${base_date}" +%Y-%m-%d
    fi
}

# ============================================================
# Build resolved URL for a given index
# ============================================================
resolve_url() {
    local idx="$1"
    local resolved="$URL"
    local inc_date

    # Replace {{INDEX}}
    resolved="${resolved//\{\{INDEX\}\}/$idx}"

    # Replace {{DATE}} with base date + idx days
    if [[ "$resolved" == *"{{DATE}}"* ]]; then
        inc_date=$(increment_date "$BASE_DATE" "$idx")
        resolved="${resolved//\{\{DATE\}\}/$inc_date}"
    fi

    echo "$resolved"
}

# ============================================================
# Worker function
# Arguments: <job_index>
# ============================================================
run_request() {
    local idx="$1"
    local result_file="$TMP_DIR/result_${idx}.txt"
    local curl_out_file="$TMP_DIR/curl_out_${idx}.txt"
    local body_out_file="$TMP_DIR/body_${idx}.txt"

    local resolved_url
    resolved_url=$(resolve_url "$idx")

    [[ "$VERBOSE" == true ]] && echo -e "  ${CYAN}[#${idx}]${RESET} ${resolved_url}"

    # Build curl command as an array (safest way to handle spaces/special chars)
    local cmd=(
        curl
        --silent
        --show-error
        --location
        --request "$METHOD"
        --max-time "$TIMEOUT"
        --write-out "\n---CURL_STATS---\nhttp_code=%{http_code}\ntime_connect=%{time_connect}\ntime_starttransfer=%{time_starttransfer}\ntime_total=%{time_total}\nsize_download=%{size_download}\n"
        --output "$body_out_file"
    )

    # Add headers
    for header in "${HEADERS[@]}"; do
        cmd+=(--header "$header")
    done

    # Add body
    if [[ -n "$BODY_FILE" ]]; then
        cmd+=(--data "@${BODY_FILE}")
    elif [[ -n "$BODY" ]]; then
        cmd+=(--data "$BODY")
    fi

    cmd+=("$resolved_url")

    local start_ms
    start_ms=$(get_ms)

    "${cmd[@]}" > "$curl_out_file" 2>&1

    local end_ms
    end_ms=$(get_ms)
    local wall_ms=$(( end_ms - start_ms ))

    # Copy body to output dir if requested
    if [[ -n "$OUTPUT_DIR" ]]; then
        cp "$body_out_file" "${OUTPUT_DIR}/response_${idx}.txt"
    fi

    local http_code time_connect time_starttransfer time_total size_download
    http_code=$(grep        '^http_code='           "$curl_out_file" | cut -d= -f2 | tr -d '[:space:]')
    time_connect=$(grep     '^time_connect='        "$curl_out_file" | cut -d= -f2 | tr -d '[:space:]')
    time_starttransfer=$(grep '^time_starttransfer=' "$curl_out_file" | cut -d= -f2 | tr -d '[:space:]')
    time_total=$(grep       '^time_total='          "$curl_out_file" | cut -d= -f2 | tr -d '[:space:]')
    size_download=$(grep    '^size_download='       "$curl_out_file" | cut -d= -f2 | tr -d '[:space:]')

    http_code=${http_code:-"ERR"}
    time_connect=${time_connect:-"0.000"}
    time_starttransfer=${time_starttransfer:-"0.000"}
    time_total=${time_total:-"0.000"}
    size_download=${size_download:-"0"}

    printf "%d\t%s\t%s\t%s\t%s\t%s\t%d\t%s\n" \
        "$idx" "$resolved_url" \
        "$http_code" \
        "$time_connect" \
        "$time_starttransfer" \
        "$time_total" \
        "$wall_ms" \
        "$size_download" \
        > "$result_file"
}

# ============================================================
# Print config summary
# ============================================================
echo ""
echo -e "${BOLD}${CYAN}=================================================${RESET}"
echo -e "${BOLD}${CYAN}       Generic Parallel HTTP Load Test           ${RESET}"
echo -e "${BOLD}${CYAN}=================================================${RESET}"
echo -e "  Method   : ${BOLD}${METHOD}${RESET}"
echo -e "  URL      : ${URL}"
echo -e "  Requests : ${NUM_REQUESTS}"
echo -e "  Timeout  : ${TIMEOUT}s"
if [[ ${#HEADERS[@]} -gt 0 ]]; then
    echo -e "  Headers  :"
    for h in "${HEADERS[@]}"; do
        # Mask Authorization header value for safety
        masked=$(echo "$h" | sed 's/\(Authorization:.*Bearer \)[^ ]*/\1[MASKED]/')
        echo -e "             ${masked}"
    done
fi
[[ -n "$BODY"      ]] && echo -e "  Body     : ${BODY}"
[[ -n "$BODY_FILE" ]] && echo -e "  Body file: ${BODY_FILE}"
[[ -n "$OUTPUT_DIR" ]] && echo -e "  Saving responses to: ${OUTPUT_DIR}/"
echo ""
echo -e "${YELLOW}Firing all ${NUM_REQUESTS} requests simultaneously...${RESET}"
[[ "$VERBOSE" == true ]] && echo ""

# ============================================================
# Launch all requests IN PARALLEL
# ============================================================
LAUNCH_MS=$(get_ms)
PIDS=()

for i in $(seq 0 $(( NUM_REQUESTS - 1 ))); do
    run_request "$i" &
    PIDS+=($!)
done

for pid in "${PIDS[@]}"; do
    wait "$pid"
done

END_MS=$(get_ms)
TOTAL_WALL=$(( END_MS - LAUNCH_MS ))

# ============================================================
# Collect rows + find min/max
# ============================================================
declare -a ROWS=()
min_total=999999
max_total=0

for i in $(seq 0 $(( NUM_REQUESTS - 1 ))); do
    result_file="$TMP_DIR/result_${i}.txt"
    if [[ -f "$result_file" ]]; then
        IFS=$'\t' read -r idx resolved_url http_code time_connect time_starttransfer time_total wall_ms size_download \
            < "$result_file"

        total_ms=$(python3 -c "print(int(float('${time_total}') * 1000))" 2>/dev/null || echo "0")

        [[ $total_ms -lt $min_total ]] && min_total=$total_ms
        [[ $total_ms -gt $max_total ]] && max_total=$total_ms

        ROWS+=("$idx|$resolved_url|$http_code|$time_connect|$time_starttransfer|$time_total|$wall_ms|$size_download|$total_ms")
    else
        ROWS+=("$i|N/A|ERR|N/A|N/A|N/A|N/A|N/A|0")
    fi
done

# ============================================================
# Print results table
# ============================================================
echo ""
echo -e "${BOLD}${CYAN}Results (sorted by job index)${RESET}"
echo -e "${BOLD}──────┬──────┬──────────────┬──────────────┬──────────────┬──────────┬──────────┬────────────────────────────────────────────${RESET}"
printf "${BOLD}%-5s │ %-4s │ %-12s │ %-12s │ %-12s │ %-8s │ %-8s │ %s${RESET}\n" \
    " Job" "HTTP" "Connect(s)" "TTFB(s)" "Total(s)" "Wall(ms)" "Bytes" "URL"
echo -e "${BOLD}──────┼──────┼──────────────┼──────────────┼──────────────┼──────────┼──────────┼────────────────────────────────────────────${RESET}"

sum_total_ms=0

for row in "${ROWS[@]}"; do
    IFS='|' read -r idx resolved_url http_code time_connect time_starttransfer time_total wall_ms size_download total_ms <<< "$row"

    if [[ "$total_ms" -eq "$max_total" ]]; then
        colour=$RED
    elif [[ "$total_ms" -eq "$min_total" ]]; then
        colour=$GREEN
    else
        colour=$YELLOW
    fi

    if [[ "$http_code" == "200" || "$http_code" == "201" || "$http_code" == "204" ]]; then
        http_colour=$GREEN
    else
        http_colour=$RED
    fi

    # Truncate long URLs for the table
    display_url="${resolved_url}"
    if [[ ${#display_url} -gt 60 ]]; then
        display_url="${display_url:0:57}..."
    fi

    printf "${colour}%-5s${RESET} │ ${http_colour}%-4s${RESET} │ %-12s │ %-12s │ ${colour}%-12s${RESET} │ ${colour}%-8s${RESET} │ %-8s │ %s\n" \
        " #${idx}" "$http_code" "$time_connect" "$time_starttransfer" "$time_total" "$wall_ms" "$size_download" "$display_url"

    sum_total_ms=$(( sum_total_ms + total_ms ))
done

echo -e "${BOLD}──────┴──────┴──────────────┴──────────────┴──────────────┴──────────┴──────────┴────────────────────────────────────────────${RESET}"

# ============================================================
# Summary statistics
# ============================================================
avg_total_ms=$(( sum_total_ms / ${#ROWS[@]} ))
slowdown=$(python3 -c "print(f'{$max_total / $min_total:.2f}')" 2>/dev/null || echo "N/A")

echo ""
echo -e "${BOLD}${CYAN}Summary${RESET}"
echo -e "  ${GREEN}Fastest response : ${min_total} ms${RESET}"
echo -e "  ${RED}Slowest response : ${max_total} ms${RESET}"
echo -e "  ${YELLOW}Average response : ${avg_total_ms} ms${RESET}"
echo -e "  ${BOLD}Slowdown factor  : ${slowdown}x  (slowest ÷ fastest)${RESET}"
echo -e "  Wall-clock total : ${TOTAL_WALL} ms  (all ${NUM_REQUESTS} requests, launch → last reply)"
[[ -n "$OUTPUT_DIR" ]] && echo -e "  Response bodies  : ${OUTPUT_DIR}/response_N.txt"
echo ""
echo -e "${CYAN}Legend: ${GREEN}fastest${RESET} │ ${YELLOW}middle${RESET} │ ${RED}slowest${RESET}"
echo ""
