#!/bin/bash

BASE_URL="http://localhost"
SUCCESS_COUNT=0
FAIL_COUNT=0

print_result() {
    if [ $1 -eq 0 ]; then
        echo "OK"
        ((SUCCESS_COUNT++))
    else
        echo "FAIL"
        ((FAIL_COUNT++))
    fi
}

test_endpoint() {
    local method=$1
    local endpoint=$2
    local data=$3
    local token=$4

    if [ -n "$token" ]; then
        response=$(curl -s -w "%{http_code}" -o /dev/null -X "$method" "$BASE_URL$endpoint" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $token" \
            -d "$data" 2>/dev/null)
    elif [ -n "$data" ]; then
        response=$(curl -s -w "%{http_code}" -o /dev/null -X "$method" "$BASE_URL$endpoint" \
            -H "Content-Type: application/json" \
            -d "$data" 2>/dev/null)
    else
        response=$(curl -s -w "%{http_code}" -o /dev/null -X "$method" "$BASE_URL$endpoint" 2>/dev/null)
    fi

    if [ "$response" = "200" ] || [ "$response" = "201" ]; then
        print_result 0
        return 0
    else
        print_result 1
        return 1
    fi
}

echo "Starting Stress Test..."
echo "======================"
echo ""

echo "Testing Admin Login (10 requests)..."
for i in {1..10}; do
    printf "Request $i: "
    test_endpoint "POST" "/api/event/auth/admin/login" '{"email":"atlanadmin@mail.com","password":"11111111"}'
done
echo ""

echo "Getting Admin Token..."
ADMIN_TOKEN=$(curl -s -X POST "$BASE_URL/api/event/auth/admin/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"atlanadmin@mail.com","password":"11111111"}' | sed -n 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

if [ -z "$ADMIN_TOKEN" ]; then
    echo "FAIL: Could not get admin token"
    exit 1
fi
echo "OK: Got admin token"
echo ""

echo "Testing Admin Events List - WITH CACHE (50 requests)..."
for i in {1..50}; do
    printf "Request $i: "
    test_endpoint "GET" "/api/event/admin/events" "" "$ADMIN_TOKEN"
done
echo ""

echo "Testing User Registration (20 requests)..."
TIMESTAMP=$(date +%s)
for i in {1..20}; do
    printf "Request $i: "
    test_endpoint "POST" "/api/user/auth/register" "{\"email\":\"stresstest${TIMESTAMP}_$i@test.com\",\"password\":\"password123\",\"name\":\"Stress User $i\"}"
done
echo ""

echo "Testing User Login (20 requests)..."
for i in {1..20}; do
    printf "Request $i: "
    test_endpoint "POST" "/api/user/auth/login" '{"email":"atlanuser1@mail.com","password":"11111111"}'
done
echo ""

echo "Getting User Token..."
USER_TOKEN=$(curl -s -X POST "$BASE_URL/api/user/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"atlanuser1@mail.com","password":"11111111"}' | sed -n 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

if [ -z "$USER_TOKEN" ]; then
    echo "FAIL: Could not get user token"
else
    echo "OK: Got user token"
    echo ""

    echo "Testing User Profile - WITH CACHE (50 requests)..."
    for i in {1..50}; do
        printf "Request $i: "
        test_endpoint "GET" "/api/user/users/profile" "" "$USER_TOKEN"
    done
    echo ""
fi

echo "Getting Event ID..."
EVENT_ID=$(curl -s "$BASE_URL/api/event/events" | sed -n 's/.*"event_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

if [ -n "$EVENT_ID" ]; then
    echo "OK: Got event ID: $EVENT_ID"
    echo ""

    echo "Testing Event Details - WITH CACHE (100 requests)..."
    for i in {1..100}; do
        printf "Request $i: "
        test_endpoint "GET" "/api/event/events/$EVENT_ID" ""
    done
    echo ""

    echo "Testing Event Availability - WITH CACHE (100 requests)..."
    for i in {1..100}; do
        printf "Request $i: "
        test_endpoint "GET" "/api/event/events/$EVENT_ID/availability" ""
    done
    echo ""
fi

echo "Testing Public Events List (50 requests)..."
for i in {1..50}; do
    printf "Request $i: "
    test_endpoint "GET" "/api/event/events" ""
done
echo ""

echo "======================"
echo "Stress Test Complete"
echo "======================"
echo "SUCCESS: $SUCCESS_COUNT"
echo "FAIL: $FAIL_COUNT"
echo "TOTAL: $((SUCCESS_COUNT + FAIL_COUNT))"
if [ $SUCCESS_COUNT -gt 0 ]; then
    SUCCESS_RATE=$(awk "BEGIN {printf \"%.2f\", ($SUCCESS_COUNT * 100) / ($SUCCESS_COUNT + $FAIL_COUNT)}")
    echo "SUCCESS RATE: $SUCCESS_RATE%"
fi
