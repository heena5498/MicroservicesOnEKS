#!/bin/bash

BASE_URL="http://localhost"
CONCURRENT=10
REQUESTS_PER_WORKER=10

SUCCESS_FILE="/tmp/stress_success_$$"
FAIL_FILE="/tmp/stress_fail_$$"
echo "0" > $SUCCESS_FILE
echo "0" > $FAIL_FILE

worker() {
    local worker_id=$1
    local endpoint=$2
    local token=$3

    for i in $(seq 1 $REQUESTS_PER_WORKER); do
        if [ -n "$token" ]; then
            response=$(curl -s -w "%{http_code}" -o /dev/null "$BASE_URL$endpoint" \
                -H "Authorization: Bearer $token" 2>/dev/null)
        else
            response=$(curl -s -w "%{http_code}" -o /dev/null "$BASE_URL$endpoint" 2>/dev/null)
        fi

        if [ "$response" = "200" ] || [ "$response" = "201" ]; then
            echo -n "."
            flock $SUCCESS_FILE -c "echo \$(($(cat $SUCCESS_FILE) + 1)) > $SUCCESS_FILE"
        else
            echo -n "x"
            flock $FAIL_FILE -c "echo \$(($(cat $FAIL_FILE) + 1)) > $FAIL_FILE"
        fi
    done
}

run_test() {
    local test_name=$1
    local endpoint=$2
    local token=$3
    local total=$((CONCURRENT * REQUESTS_PER_WORKER))

    echo ""
    echo "Test: $test_name"
    echo "Running $total requests ($CONCURRENT concurrent workers x $REQUESTS_PER_WORKER requests)"
    echo -n "Progress: "

    local start_time=$(date +%s.%N)

    for i in $(seq 1 $CONCURRENT); do
        worker $i "$endpoint" "$token" &
    done

    wait

    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    local rps=$(echo "scale=2; $total / $duration" | bc)

    echo ""
    echo "Duration: ${duration}s | Requests/sec: $rps"
}

echo "========================================="
echo "Concurrent Stress Test"
echo "========================================="
echo "Configuration: $CONCURRENT workers, $REQUESTS_PER_WORKER requests each"

echo ""
echo "Getting authentication tokens..."
ADMIN_TOKEN=$(curl -s -X POST "$BASE_URL/api/event/auth/admin/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"atlanadmin@mail.com","password":"11111111"}' | sed -n 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

USER_TOKEN=$(curl -s -X POST "$BASE_URL/api/user/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"atlanuser1@mail.com","password":"11111111"}' | sed -n 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

EVENT_ID=$(curl -s "$BASE_URL/api/event/events" | sed -n 's/.*"event_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

if [ -z "$ADMIN_TOKEN" ] || [ -z "$USER_TOKEN" ] || [ -z "$EVENT_ID" ]; then
    echo "FAIL: Could not initialize test data"
    exit 1
fi

echo "OK: Authentication ready"

run_test "Admin Auth (JWT Cached)" "/api/event/admin/events" "$ADMIN_TOKEN"

run_test "User Auth (JWT Cached)" "/api/user/users/profile" "$USER_TOKEN"

run_test "Event Details (Redis Cached)" "/api/event/events/$EVENT_ID" ""

run_test "Event Availability" "/api/event/events/$EVENT_ID/availability" ""

run_test "Public Events List" "/api/event/events" ""

SUCCESS_COUNT=$(cat $SUCCESS_FILE)
FAIL_COUNT=$(cat $FAIL_FILE)

echo ""
echo "========================================="
echo "Test Summary"
echo "========================================="
echo "SUCCESS: $SUCCESS_COUNT"
echo "FAIL: $FAIL_COUNT"
echo "TOTAL: $((SUCCESS_COUNT + FAIL_COUNT))"
if [ $SUCCESS_COUNT -gt 0 ]; then
    SUCCESS_RATE=$(awk "BEGIN {printf \"%.2f\", ($SUCCESS_COUNT * 100) / ($SUCCESS_COUNT + $FAIL_COUNT)}")
    echo "SUCCESS RATE: $SUCCESS_RATE%"
fi

rm -f $SUCCESS_FILE $FAIL_FILE
