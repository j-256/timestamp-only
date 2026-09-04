#!/bin/bash

set -eu

readonly EXPECTED_SUCCESS=0
readonly EXPECTED_USAGE=2
readonly EXPECTED_DEPENDENCY=3

script_directory=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH='' cd -- "$script_directory/../.." && pwd)
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/timestamp-only-cli-tests.XXXXXX")
empty_path="$test_directory/empty-path"
stdout_path="$test_directory/stdout"
stderr_path="$test_directory/stderr"
mkdir -p "$empty_path"
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM

last_status=0

run_command() {
    set +e
    "$@" >"$stdout_path" 2>"$stderr_path"
    last_status=$?
    set -e
}

fail() {
    printf 'CommandLineTests: %s\n' "$1" >&2
    printf '%s\n' '--- stdout ---' >&2
    sed 's/^/  /' "$stdout_path" >&2
    printf '%s\n' '--- stderr ---' >&2
    sed 's/^/  /' "$stderr_path" >&2
    exit 1
}

assert_status() {
    local expected_status

    expected_status=$1
    if [ "$last_status" -ne "$expected_status" ]; then
        fail "expected status $expected_status, got $last_status"
    fi
}

assert_stdout_present() {
    [ -s "$stdout_path" ] || fail 'expected stdout'
}

assert_stdout_empty() {
    [ ! -s "$stdout_path" ] || fail 'expected empty stdout'
}

assert_stderr_empty() {
    [ ! -s "$stderr_path" ] || fail 'expected empty stderr'
}

assert_stderr_contains() {
    grep -Fq -- "$1" "$stderr_path" || fail "expected stderr to contain: $1"
}

for command_name in build-app create-dmg notarize-dmg verify-app verify-dmg version; do
    command_path="$repository_root/scripts/$command_name"

    run_command "$command_path" -h
    assert_status "$EXPECTED_SUCCESS"
    assert_stdout_present
    assert_stderr_empty

    run_command "$command_path" --help
    assert_status "$EXPECTED_SUCCESS"
    assert_stdout_present
    assert_stderr_empty

    run_command "$command_path" --unknown-option
    assert_status "$EXPECTED_USAGE"
    assert_stdout_empty
    assert_stderr_contains 'unknown option'
done

run_command env PATH="$empty_path" "$repository_root/scripts/build-app"
assert_status "$EXPECTED_DEPENDENCY"

run_command env PATH="$empty_path" "$repository_root/scripts/create-dmg"
assert_status "$EXPECTED_DEPENDENCY"

run_command "$repository_root/scripts/notarize-dmg"
assert_status "$EXPECTED_USAGE"
assert_stderr_contains 'is required'

run_command env PATH="$empty_path" "$repository_root/scripts/verify-app"
assert_status "$EXPECTED_DEPENDENCY"

run_command env PATH="$empty_path" "$repository_root/scripts/verify-dmg"
assert_status "$EXPECTED_DEPENDENCY"

run_command env PATH="$empty_path" "$repository_root/scripts/build-app" \
    --architecture=arm64 \
    --build-number=2 \
    --configuration=debug \
    --output=build \
    --signing-identity=- \
    --version=0.1.0
assert_status "$EXPECTED_DEPENDENCY"
assert_stdout_empty
assert_stderr_contains 'required command not found'

run_command env PATH="$empty_path" "$repository_root/scripts/build-app" \
    -aarm64 \
    -b2 \
    -cdebug \
    -obuild \
    -s- \
    -V0.1.0
assert_status "$EXPECTED_DEPENDENCY"

run_command "$repository_root/scripts/build-app" --output=
assert_status "$EXPECTED_USAGE"
assert_stderr_contains 'requires a value'

run_command env PATH="$empty_path" "$repository_root/scripts/build-app" --
assert_status "$EXPECTED_DEPENDENCY"

run_command env PATH="$empty_path" "$repository_root/scripts/create-dmg" --app=example.app --output=build
assert_status "$EXPECTED_DEPENDENCY"

run_command env PATH="$empty_path" "$repository_root/scripts/create-dmg" -aexample.app -obuild
assert_status "$EXPECTED_DEPENDENCY"

run_command env PATH="$empty_path" "$repository_root/scripts/create-dmg" -f -aexample.app -obuild
assert_status "$EXPECTED_DEPENDENCY"

run_command "$repository_root/scripts/create-dmg" --app=
assert_status "$EXPECTED_USAGE"
assert_stderr_contains 'requires a value'

run_command env PATH="$empty_path" "$repository_root/scripts/create-dmg" --
assert_status "$EXPECTED_DEPENDENCY"

invalid_version_app="$test_directory/Invalid Version.app"
mkdir -p "$invalid_version_app/Contents"
plutil -create xml1 "$invalid_version_app/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string '../escape' "$invalid_version_app/Contents/Info.plist"
run_command "$repository_root/scripts/create-dmg" --app "$invalid_version_app" --output "$test_directory"
assert_status 1
assert_stdout_empty
assert_stderr_contains 'invalid CFBundleShortVersionString'

run_command env PATH="$empty_path" "$repository_root/scripts/notarize-dmg" \
    --keychain-profile=notary-profile \
    artifact.dmg \
    --signing-identity='Developer ID Application: Example'
assert_status "$EXPECTED_DEPENDENCY"

run_command env PATH="$empty_path" "$repository_root/scripts/notarize-dmg" \
    -pnotary-profile \
    -s'Developer ID Application: Example' \
    -- \
    -artifact.dmg
assert_status "$EXPECTED_DEPENDENCY"

run_command "$repository_root/scripts/notarize-dmg" --keychain-profile=
assert_status "$EXPECTED_USAGE"
assert_stderr_contains 'requires a value'

run_command "$repository_root/scripts/notarize-dmg" \
    --keychain-profile profile \
    --signing-identity identity \
    --log=
assert_status "$EXPECTED_USAGE"
assert_stderr_contains 'requires a value'

notarize_fixture="$test_directory/notarize-fixture.dmg"
printf '%s\n' 'not a disk image' >"$notarize_fixture"
printf '%s\n' 'unrelated checksum content' >"$notarize_fixture.sha256"
run_command "$repository_root/scripts/notarize-dmg" \
    --keychain-profile profile \
    --signing-identity identity \
    "$notarize_fixture"
assert_status "$EXPECTED_USAGE"
assert_stderr_contains 'existing checksum does not describe the input DMG'
[ "$(sed -n '1p' "$notarize_fixture.sha256")" = 'unrelated checksum content' ] || \
    fail 'notarization changed an unrelated checksum'

rm -f "$notarize_fixture.sha256"
run_command "$repository_root/scripts/notarize-dmg" \
    --keychain-profile profile \
    --signing-identity identity \
    --result "$test_directory/./notarize-fixture.dmg.sha256" \
    "$notarize_fixture"
assert_status "$EXPECTED_USAGE"
assert_stderr_contains '--result must not replace the checksum'

run_command "$repository_root/scripts/verify-app" --release
assert_status "$EXPECTED_USAGE"
assert_stderr_contains '--team-id is required'

run_command "$repository_root/scripts/verify-app" --team-id TEAMID
assert_status "$EXPECTED_USAGE"
assert_stderr_contains '--team-id requires --release'

run_command env PATH="$empty_path" "$repository_root/scripts/verify-app" -- -example.app
assert_status "$EXPECTED_DEPENDENCY"

run_command "$repository_root/scripts/verify-app" example.app another.app
assert_status "$EXPECTED_USAGE"
assert_stderr_contains 'unexpected argument'

run_command env PATH="$empty_path" "$repository_root/scripts/verify-dmg" -- -example.dmg
assert_status "$EXPECTED_DEPENDENCY"

run_command "$repository_root/scripts/verify-dmg" example.dmg another.dmg
assert_status "$EXPECTED_USAGE"
assert_stderr_contains 'unexpected argument'

run_command "$repository_root/scripts/verify-dmg" --release
assert_status "$EXPECTED_USAGE"
assert_stderr_contains '--team-id is required'

run_command "$repository_root/scripts/version"
assert_status "$EXPECTED_USAGE"
assert_stderr_contains 'VERSION is required'

run_command "$repository_root/scripts/version" invalid
assert_status "$EXPECTED_USAGE"
assert_stderr_contains 'numeric X.Y.Z'

printf 'Command-line interface tests passed\n'
