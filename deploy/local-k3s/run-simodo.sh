#!/usr/bin/env sh
set -eu

mkdir -p /tmp/simodo/bin \
  /tmp/simodo/data/stellar \
  /tmp/simodo/data/contracts \
  /tmp/simodo/tmp/logs/work \
  /tmp/simodo/tmp/logs \
  /tmp/simodo/db

cp /etc/xdg/simodo/stellar/base-setup.json /tmp/simodo/data/stellar/base-setup.json
cp /etc/xdg/simodo/stellar/station-setup.json /tmp/simodo/data/stellar/station-setup.json
cp /usr/share/simodo/contracts/initial-contracts.s-script /tmp/simodo/data/contracts/initial-contracts.s-script

cp /app/src/students/-base-setup.local.s-script /app/src/students/-base-setup.s-script
cp /app/src/training-plans/-base-setup.local.s-script /app/src/training-plans/-base-setup.s-script
cp /app/src/exam-applications/-base-setup.local.s-script /app/src/exam-applications/-base-setup.s-script

cd /tmp/simodo/bin

simodo-stellar-base 2022 /tmp/simodo/db >/tmp/base.log 2>&1 &
base_pid=$!

wait_for_base() {
  attempt=0

  while ! curl -sS --max-time 2 http://127.0.0.1:2022/ >/dev/null 2>&1; do
    attempt=$((attempt + 1))

    if [ "$attempt" -ge 30 ]; then
      echo "simodo-stellar-base did not become ready"
      return 1
    fi

    sleep 1
  done
}

initialize_aggregate() {
  database="$1"
  aggregate="$2"
  url="http://127.0.0.1:2022/$database/$aggregate"

  id="$(curl -fsS --max-time 5 \
    -H 'Content-Type: application/json' \
    -X POST \
    --data '{}' \
    "$url")"

  curl -fsS --max-time 5 -X DELETE "$url/$id" >/dev/null
  echo "Initialized empty aggregate $database/$aggregate"
}

wait_for_base
initialize_aggregate drivingschool-students students
initialize_aggregate drivingschool-training plans
initialize_aggregate drivingschool-exams applications

simodo-stellar-station 8081 /app/src >/tmp/students.log 2>&1 &
students_pid=$!
simodo-stellar-station 8082 /app/src >/tmp/training.log 2>&1 &
training_pid=$!
simodo-stellar-station 8083 /app/src >/tmp/exams.log 2>&1 &
exams_pid=$!

tail -n +1 -F /tmp/base.log /tmp/students.log /tmp/training.log /tmp/exams.log &
tail_pid=$!

cleanup() {
  kill "$base_pid" "$students_pid" "$training_pid" "$exams_pid" "$tail_pid" 2>/dev/null || true
}

trap cleanup INT TERM EXIT

while :; do
  for process in \
    "$base_pid:simodo-stellar-base" \
    "$students_pid:students station" \
    "$training_pid:training station" \
    "$exams_pid:exams station"
  do
    pid="${process%%:*}"
    name="${process#*:}"

    if ! kill -0 "$pid" 2>/dev/null; then
      echo "$name exited unexpectedly"
      set +e
      wait "$pid"
      status=$?
      set -e
      echo "$name exit status: $status"
      exit 1
    fi
  done

  sleep 2
done
