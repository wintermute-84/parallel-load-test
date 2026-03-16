chmod +x load_test.sh

# Simple GET - same URL repeated
./load_test.sh \
  -m GET \
  -n 10 \
  -u 'https://api.example.com/health' \
  -H 'Authorization: Bearer YOUR_TOKEN' \
  -H 'Accept: application/json'

# GET with auto-incrementing date
./load_test.sh \
  -m GET \
  -n 10 \
  -u 'https://api.example.com/.../search?referenceDate={{DATE}}&itemNumber=11111' \
  -D 2026-03-16 \
  -H 'Authorization: Bearer YOUR_TOKEN'

# GET with index in URL
./load_test.sh \
  -m GET \
  -n 5 \
  -u 'https://api.example.com/users/{{INDEX}}' \
  -H 'Authorization: Bearer YOUR_TOKEN'

# POST with inline JSON body
./load_test.sh \
  -m POST \
  -n 5 \
  -u 'https://api.example.com/orders' \
  -H 'Authorization: Bearer YOUR_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{"item": "widget", "qty": 1}'

# POST with body from file + save responses
./load_test.sh \
  -m POST \
  -n 20 \
  -u 'https://api.example.com/orders' \
  -H 'Authorization: Bearer YOUR_TOKEN' \
  -H 'Content-Type: application/json' \
  -f ./payload.json \
  -o ./responses

# DELETE with verbose URL logging
./load_test.sh \
  -m DELETE \
  -n 5 \
  -u 'https://api.example.com/sessions/{{INDEX}}' \
  -H 'Authorization: Bearer YOUR_TOKEN' \
  -t 10 \
  -v
