#!/usr/bin/env bash
# Acceptance checks for the dev-boilerplate (run: wsl bash .agent/check.sh)
cd /home/laravel/projects/fastapi_example || exit 1

pass=0; fail=0
check() {
  desc="$1"; url="$2"; expect="$3"
  code=$(curl -s -o /tmp/check_body -w '%{http_code}' --max-time 15 "$url")
  if [ "$code" = "$expect" ]; then st=PASS; pass=$((pass+1)); else st=FAIL; fail=$((fail+1)); fi
  printf '%-38s GET %-40s -> %s (expect %s) %s\n' "$desc" "$url" "$code" "$expect" "$st"
}

echo "===== dev-boilerplate acceptance checks ====="
check "frontend via Nginx"           "http://localhost/"                    200
check "API health via Nginx"         "http://localhost/api/v1/health"       200
check "Swagger UI via Nginx"         "http://localhost/docs"                200
check "OpenAPI schema via Nginx"     "http://localhost/openapi.json"        200
check "backend direct (docs)"        "http://localhost:8000/docs"           200
check "backend direct (health)"      "http://localhost:8000/api/v1/health"  200
check "Vite module via Nginx"        "http://localhost/src/main.js"         200
check "Vite HMR client via Nginx"    "http://localhost/@vite/client"        200

echo
echo "health body (via Nginx): $(curl -s --max-time 15 http://localhost/api/v1/health)"
echo "frontend first line:     $(curl -s --max-time 15 http://localhost/ | head -n 1)"

echo
echo "===== summary: PASS=$pass FAIL=$fail ====="
[ "$fail" = 0 ]
