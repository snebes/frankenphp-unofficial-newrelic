#!/usr/bin/env bash
# Load a built newrelic.so into FrankenPHP and hammer it with concurrent requests.
#
# Usage: smoke-test.sh <path/to/newrelic.so> <php-version> <expected-agent-version>
#   e.g. smoke-test.sh out/newrelic.so 8.4 12.6.0.34
#
# If no dunglas/frankenphp image exists for the PHP version yet, the full test is run
# in SERVERSIDEUP_IMAGE (e.g. serversideup/php:8.6-rc-frankenphp-trixie) when set.
# If that is unavailable too and FALLBACK_IMAGE is set, only a CLI load check is run
# in that image.
set -euo pipefail

so="$1"
php_version="$2"
expected="$3"

image="dunglas/frankenphp:1-php${php_version}"
# Per-image settings; overridden below when falling back to serversideup/php.
container_port=80
docroot=/app/public
container_env=(-e SERVER_NAME=:80 -e FRANKENPHP_CONFIG="num_threads 16")
name="nr-smoke-${php_version}-$$"
port="${SMOKE_PORT:-18080}"
requests="${SMOKE_REQUESTS:-400}"
parallel="${SMOKE_PARALLEL:-32}"
workdir="$(mktemp -d)"

cleanup() {
  status=$?
  if [[ ${status} -ne 0 ]]; then
    echo "::group::Container logs"
    docker logs "${name}" 2>&1 | tail -n 100 || true
    echo "::endgroup::"
    echo "::group::Agent log"
    docker exec "${name}" cat /tmp/newrelic.log 2>/dev/null | tail -n 100 || true
    echo "::endgroup::"
  fi
  docker rm -f "${name}" >/dev/null 2>&1 || true
  rm -rf "${workdir}"
}
trap cleanup EXIT

fail() {
  echo "::error::${1}"
  exit 1
}

cat > "${workdir}/newrelic.ini" <<'EOF'
extension=/opt/newrelic.so
newrelic.enabled=1
newrelic.license=0000000000000000000000000000000000000000
newrelic.appname=smoke-test
newrelic.daemon.dont_launch=3
newrelic.loglevel=info
newrelic.logfile=/tmp/newrelic.log
EOF

cat > "${workdir}/index.php" <<'EOF'
<?php
$sum = 0;
for ($i = 0; $i < 20000; $i++) {
    $sum += strlen(md5((string) $i));
}
newrelic_name_transaction('/smoke');
newrelic_add_custom_parameter('sum', $sum);
echo 'newrelic=', phpversion('newrelic'), "\n";
EOF

available=0
if docker pull --quiet "${image}" >/dev/null 2>&1; then
  available=1
elif [[ "${SERVERSIDEUP_IMAGE:-}" == serversideup/* ]]; then
  echo "::warning::${image} is not available; trying ${SERVERSIDEUP_IMAGE}"
  image="${SERVERSIDEUP_IMAGE}"
  container_port=8080
  docroot=/var/www/html/public
  container_env=(-e FRANKENPHP_CONFIG="num_threads 16")
  if docker pull --quiet "${image}" >/dev/null 2>&1; then
    available=1
  fi
fi

if [[ "${available}" -eq 0 ]]; then
  [[ -n "${FALLBACK_IMAGE:-}" ]] || fail "${image} is not available"
  echo "::warning::${image} is not available; only checking that the extension loads in ${FALLBACK_IMAGE}"
  docker create --name "${name}" "${FALLBACK_IMAGE}" \
    php -d display_startup_errors=1 -d extension=/opt/newrelic.so \
    -r 'echo phpversion("newrelic"), PHP_ZTS ? " zts" : " nts", "\n";' >/dev/null
  docker cp "${so}" "${name}:/opt/newrelic.so"
  result="$(docker start -a "${name}")"
  [[ "${result}" == "${expected} zts" ]] || fail "${FALLBACK_IMAGE} reported '${result}', expected '${expected} zts'"
  echo "newrelic ${expected} loaded in ${FALLBACK_IMAGE} (ZTS)"
  exit 0
fi

docker create --name "${name}" -p "127.0.0.1:${port}:${container_port}" \
  "${container_env[@]}" "${image}" >/dev/null
docker cp "${so}" "${name}:/opt/newrelic.so"
docker cp "${workdir}/newrelic.ini" "${name}:/usr/local/etc/php/conf.d/zz-newrelic.ini"
docker cp "${workdir}/index.php" "${name}:${docroot}/index.php"
docker start "${name}" >/dev/null

echo "--- CLI load"
cli_version="$(docker exec "${name}" php -d display_startup_errors=1 -r 'echo phpversion("newrelic");')"
[[ "${cli_version}" == "${expected}" ]] || fail "CLI reported '${cli_version}', expected '${expected}'"
echo "newrelic ${cli_version} loaded in ${image}"

echo "--- Wait for FrankenPHP"
body=""
for _ in $(seq 1 30); do
  body="$(curl -fsS "http://127.0.0.1:${port}/" 2>/dev/null || true)"
  [[ -n "${body}" ]] && break
  sleep 1
done
[[ "${body}" == "newrelic=${expected}" ]] || fail "Unexpected response: '${body}'"
echo "${body}"

echo "--- ${requests} requests, ${parallel} concurrent"
codes="$(seq 1 "${requests}" | xargs -P "${parallel}" -I{} \
  curl -s -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:${port}/")"
echo "${codes}" | sort | uniq -c
ok="$(echo "${codes}" | grep -c '^200$' || true)"
[[ "${ok}" -eq "${requests}" ]] || fail "Only ${ok}/${requests} requests returned 200"

[[ "$(docker inspect -f '{{.State.Running}}' "${name}")" == "true" ]] || fail "FrankenPHP exited during load"
if docker logs "${name}" 2>&1 | grep -Eiq 'segfault|SIGSEGV|SIGABRT|core dumped|PHP Fatal error'; then
  fail "Crash or fatal error in FrankenPHP logs"
fi

docker exec "${name}" grep -q "zts=yes sapi='frankenphp'" /tmp/newrelic.log \
  || fail "Agent log does not show zts=yes sapi='frankenphp'"

echo "Smoke test passed"
