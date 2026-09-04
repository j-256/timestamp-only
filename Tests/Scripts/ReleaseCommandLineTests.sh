#!/bin/bash

set -eu

readonly EXPECTED_SUCCESS=0
readonly EXPECTED_FAILURE=1
readonly EXPECTED_USAGE=2

script_directory=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH='' cd -- "$script_directory/../.." && pwd)
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/timestamp-only-release-tests.XXXXXX")
stdout_path="$test_directory/stdout"
stderr_path="$test_directory/stderr"
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM

last_status=0

run_command() {
    set +e
    "$@" >"$stdout_path" 2>"$stderr_path"
    last_status=$?
    set -e
}

fail() {
    printf 'ReleaseCommandLineTests: %s\n' "$1" >&2
    printf '%s\n' '--- stdout ---' >&2
    sed 's/^/  /' "$stdout_path" >&2
    printf '%s\n' '--- stderr ---' >&2
    sed 's/^/  /' "$stderr_path" >&2
    exit 1
}

assert_status() {
    local expected_status

    expected_status=$1
    [ "$last_status" -eq "$expected_status" ] || \
        fail "expected status $expected_status, got $last_status"
}

assert_stdout_present() {
    [ -s "$stdout_path" ] || fail 'expected stdout'
}

assert_stderr_contains() {
    grep -Fq -- "$1" "$stderr_path" || fail "expected stderr to contain: $1"
}

release_command="$repository_root/scripts/release"

run_command "$release_command" -h
assert_status "$EXPECTED_SUCCESS"
assert_stdout_present

run_command "$release_command" --help
assert_status "$EXPECTED_SUCCESS"
assert_stdout_present

run_command "$release_command"
assert_status "$EXPECTED_USAGE"
assert_stderr_contains 'prepare or publish is required'

run_command "$release_command" unknown
assert_status "$EXPECTED_USAGE"
assert_stderr_contains 'unknown command'

run_command "$release_command" prepare --yes
assert_status "$EXPECTED_USAGE"
assert_stderr_contains 'unknown option'

run_command "$release_command" publish --keychain-profile profile
assert_status "$EXPECTED_USAGE"
assert_stderr_contains 'only valid with prepare'

run_command "$release_command" prepare --keychain-profile=
assert_status "$EXPECTED_USAGE"
assert_stderr_contains 'requires a value'

fixture_repository="$test_directory/repository"
fixture_remote="$test_directory/origin.git"
fake_bin="$test_directory/bin"
fake_log="$test_directory/tool.log"
github_state="$test_directory/github"
mkdir -p "$fixture_repository/scripts" "$fake_bin" "$github_state"
fixture_repository=$(CDPATH='' cd -- "$fixture_repository" && pwd)
cp "$repository_root/scripts/release" "$fixture_repository/scripts/release"
cp "$repository_root/scripts/version" "$fixture_repository/scripts/version"
cp "$repository_root/.gitignore" "$fixture_repository/.gitignore"
printf '%s\n' '0.1.0' >"$fixture_repository/VERSION"
printf '%s\n' '1' >"$fixture_repository/BUILD_NUMBER"

cat >"$fixture_repository/scripts/fake-release-tool" <<'EOF'
#!/bin/bash

set -eu

tool_name=${0##*/}
printf '%s %s\n' "$tool_name" "$*" >>"$TEST_TOOL_LOG"
repository_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
output_directory=''
result_path=''
log_path=''
dmg_path=''

while [ "$#" -gt 0 ]; do
    case "$1" in
        --output)
            output_directory=$2
            shift 2
            ;;
        --result)
            result_path=$2
            shift 2
            ;;
        --log)
            log_path=$2
            shift 2
            ;;
        --build-number|--signing-identity|--team-id|--version|--keychain-profile)
            shift 2
            ;;
        --release|--force)
            shift
            ;;
        *.dmg)
            dmg_path=$1
            shift
            ;;
        *)
            shift
            ;;
    esac
done

case "$tool_name" in
    build-app)
        mkdir -p "$output_directory/Timestamp Only.app"
        ;;
    create-dmg)
        version=$(sed -n '1p' "$repository_root/VERSION")
        dmg_path="$output_directory/Timestamp-Only-${version}.dmg"
        printf 'fixture release bytes\n' >"$dmg_path"
        (
            cd "$output_directory"
            shasum -a 256 "${dmg_path##*/}" >"${dmg_path##*/}.sha256"
        )
        ;;
    notarize-dmg)
        plutil -create xml1 "$result_path"
        plutil -insert status -string Accepted "$result_path"
        plutil -insert id -string 00000000-0000-0000-0000-000000000001 "$result_path"
        printf '%s\n' '{"issues":[]}' >"$log_path"
        (
            cd "${dmg_path%/*}"
            shasum -a 256 "${dmg_path##*/}" >"${dmg_path##*/}.sha256"
        )
        ;;
    verify-app)
        ;;
    verify-dmg)
        [ -f "$dmg_path" ]
        [ -f "$dmg_path.sha256" ]
        ;;
esac
EOF
chmod 755 "$fixture_repository/scripts/fake-release-tool"
for tool_name in build-app create-dmg notarize-dmg verify-app verify-dmg; do
    ln -s fake-release-tool "$fixture_repository/scripts/$tool_name"
done

cat >"$fake_bin/fake-system-tool" <<'EOF'
#!/bin/bash

set -eu

tool_name=${0##*/}
printf '%s %s\n' "$tool_name" "$*" >>"$TEST_TOOL_LOG"

case "$tool_name" in
    make)
        if [ "${TEST_MAKE_DIRTY:-0}" = '1' ]; then
            repository_directory=''
            previous_argument=''
            for argument in "$@"; do
                if [ "$previous_argument" = '-C' ]; then
                    repository_directory=$argument
                    break
                fi
                previous_argument=$argument
            done
            [ -n "$repository_directory" ]
            printf '%s\n' 'created during checks' >"$repository_directory/check-created-file"
        fi
        exit 0
        ;;
    swift)
        exit 0
        ;;
    security)
        printf '%s\n' '  1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Developer ID Application: Test Signer (TESTTEAM01)"'
        printf '%s\n' '     1 valid identities found'
        ;;
    xcrun)
        printf '%s\n' '{}'
        ;;
    gh)
        group=$1
        action=$2
        shift 2
        case "$group:$action" in
            repo:view)
                printf '%s\n' "${TEST_REPOSITORY:-j-256/timestamp-only}"
                ;;
            run:list)
                if [ "${TEST_CI_SUCCESS:-1}" = '1' ]; then
                    printf '%s\n' "$(git rev-parse HEAD)"
                fi
                ;;
            api:graphql)
                if [ -f "$TEST_GITHUB_STATE/state" ]; then
                    sed -n '1p' "$TEST_GITHUB_STATE/state"
                else
                    printf '%s\n' 'absent'
                fi
                ;;
            release:list)
                if [ -f "$TEST_GITHUB_STATE/state" ]; then
                    state=$(sed -n '1p' "$TEST_GITHUB_STATE/state")
                    case " $* " in
                        *' isDraft,tagName '*)
                            if [ "$state" = 'draft' ]; then
                                printf 'v0.1.0\ttrue\n'
                            else
                                printf 'v0.1.0\tfalse\n'
                            fi
                            ;;
                        *) printf '%s\n' 'v0.1.0' ;;
                    esac
                fi
                ;;
            release:create)
                tag=$1
                shift
                mkdir -p "$TEST_GITHUB_STATE/assets"
                while [ "$#" -gt 0 ] && [ -f "$1" ]; do
                    cp "$1" "$TEST_GITHUB_STATE/assets/"
                    shift
                done
                printf '%s\n' draft >"$TEST_GITHUB_STATE/state"
                printf '%s\n' "$tag" >"$TEST_GITHUB_STATE/tag"
                ;;
            release:view)
                case " $* " in
                    *' assets '*)
                        if [ -d "$TEST_GITHUB_STATE/assets" ]; then
                            for asset_path in "$TEST_GITHUB_STATE/assets/"*; do
                                [ -f "$asset_path" ] || continue
                                basename "$asset_path"
                            done
                        fi
                        ;;
                    *' url '*)
                        printf '%s\n' 'https://github.test/j-256/timestamp-only/releases/tag/v0.1.0'
                        ;;
                    *' isDraft,url '*)
                        if [ "$(sed -n '1p' "$TEST_GITHUB_STATE/state")" = 'published' ]; then
                            printf '%s\n' 'https://github.test/j-256/timestamp-only/releases/tag/v0.1.0'
                        fi
                        ;;
                esac
                ;;
            release:upload)
                shift
                cp "$1" "$TEST_GITHUB_STATE/assets/"
                ;;
            release:download)
                if [ "${TEST_FAIL_DOWNLOAD:-0}" = '1' ]; then
                    exit 1
                fi
                download_directory=''
                while [ "$#" -gt 0 ]; do
                    case "$1" in
                        --dir)
                            download_directory=$2
                            shift 2
                            ;;
                        *) shift ;;
                    esac
                done
                cp "$TEST_GITHUB_STATE/assets/"* "$download_directory/"
                ;;
            release:edit)
                printf '%s\n' published >"$TEST_GITHUB_STATE/state"
                ;;
            *)
                printf 'unexpected gh command: %s %s\n' "$group" "$action" >&2
                exit 1
                ;;
        esac
        ;;
esac
EOF
chmod 755 "$fake_bin/fake-system-tool"
for tool_name in gh make security swift xcrun; do
    ln -s fake-system-tool "$fake_bin/$tool_name"
done

publish_expect="$test_directory/publish.exp"
cat >"$publish_expect" <<'EOF'
set timeout 30
spawn env PATH=$env(TEST_EXEC_PATH) $env(TEST_RELEASE_COMMAND) publish
expect {
    -re {Publish .+\? \[y/N\] $} { send "yes\r" }
    timeout { exit 124 }
    eof { exit 1 }
}
expect {
    -re {Make v[0-9.]+ public\? \[y/N\] $} { send "yes\r" }
    timeout { exit 124 }
    eof { exit 1 }
}
expect eof
set child_status [wait]
exit [lindex $child_status 3]
EOF

git init --bare "$fixture_remote" >/dev/null
git -C "$fixture_repository" init -b main >/dev/null
git -C "$fixture_repository" config user.name 'Release Test'
git -C "$fixture_repository" config user.email 'release-test@example.invalid'
git -C "$fixture_repository" add .gitignore BUILD_NUMBER VERSION scripts
git -C "$fixture_repository" commit -m 'fixture' >/dev/null
git -C "$fixture_repository" remote add origin "$fixture_remote"
git -C "$fixture_repository" push -u origin main >/dev/null

export TEST_TOOL_LOG=$fake_log
export TEST_GITHUB_STATE=$github_state
test_path="$fake_bin:$PATH"

printf '%s\n' 'dirty' >"$fixture_repository/untracked"
run_command env PATH="$test_path" "$fixture_repository/scripts/release" prepare
assert_status "$EXPECTED_USAGE"
assert_stderr_contains 'working tree must be clean'
rm -f "$fixture_repository/untracked"

run_command env PATH="$test_path" TEST_REPOSITORY=j-256/wrong-repository "$fixture_repository/scripts/release" prepare
assert_status "$EXPECTED_USAGE"
assert_stderr_contains 'origin resolves to j-256/wrong-repository'

run_command env PATH="$test_path" TEST_CI_SUCCESS=0 "$fixture_repository/scripts/release" prepare
assert_status "$EXPECTED_FAILURE"
assert_stderr_contains 'CI has not succeeded'

run_command env PATH="$test_path" "$fixture_repository/scripts/release" prepare
assert_status "$EXPECTED_SUCCESS"
candidate_directory=$(sed -n '1p' "$stdout_path")
[ "$candidate_directory" = "$fixture_repository/release-candidates/v0.1.0-1" ] || \
    fail "unexpected candidate directory: $candidate_directory"
[ -f "$candidate_directory/release.plist" ] || fail 'release manifest was not created'
[ "$(plutil -extract Commit raw -o - "$candidate_directory/release.plist")" = "$(git -C "$fixture_repository" rev-parse HEAD)" ] || \
    fail 'release manifest commit differs'
[ "$(plutil -extract TeamID raw -o - "$candidate_directory/release.plist")" = 'TESTTEAM01' ] || \
    fail 'release manifest Team ID differs'
grep -Fq 'notarize-dmg ' "$fake_log" || fail 'notarization tool was not called'
grep -Fq 'verify-dmg ' "$fake_log" || fail 'final verification tool was not called'
grep -Fq 'gh api graphql' "$fake_log" || fail 'release state was not queried exactly'
if grep -Fq 'gh release create' "$fake_log"; then
    fail 'prepare attempted publication'
fi
if git -C "$fixture_repository" show-ref --verify --quiet refs/tags/v0.1.0; then
    fail 'prepare created a tag'
fi

run_command env PATH="$test_path" "$fixture_repository/scripts/release" prepare
assert_status "$EXPECTED_USAGE"
assert_stderr_contains 'release candidate already exists'

run_command env PATH="$test_path" "$fixture_repository/scripts/release" publish
assert_status "$EXPECTED_USAGE"
assert_stderr_contains 'interactive terminal'

run_command env \
    TEST_EXEC_PATH="$test_path" \
    TEST_RELEASE_COMMAND="$fixture_repository/scripts/release" \
    TEST_FAIL_DOWNLOAD=1 \
    /usr/bin/expect "$publish_expect"
assert_status "$EXPECTED_FAILURE"
[ "$(sed -n '1p' "$github_state/state")" = 'draft' ] || fail 'failed verification did not retain the draft'
[ "$(git --git-dir="$fixture_remote" rev-parse 'v0.1.0^{}')" = "$(git -C "$fixture_repository" rev-parse HEAD)" ] || \
    fail 'partial publication did not retain the exact remote tag'

run_command env \
    TEST_EXEC_PATH="$test_path" \
    TEST_RELEASE_COMMAND="$fixture_repository/scripts/release" \
    /usr/bin/expect "$publish_expect"
assert_status "$EXPECTED_SUCCESS"
grep -Fq 'https://github.test/' "$stdout_path" || fail 'published release URL is missing'
[ "$(sed -n '1p' "$github_state/state")" = 'published' ] || fail 'release was not published'
[ "$(git -C "$fixture_repository" rev-parse 'v0.1.0^{}')" = "$(git -C "$fixture_repository" rev-parse HEAD)" ] || \
    fail 'release tag points to the wrong commit'
[ "$(git --git-dir="$fixture_remote" rev-parse 'v0.1.0^{}')" = "$(git -C "$fixture_repository" rev-parse HEAD)" ] || \
    fail 'remote release tag points to the wrong commit'

printf '%s\n' 'unexpected' >"$github_state/assets/unexpected.txt"
run_command env PATH="$test_path" "$fixture_repository/scripts/release" publish
assert_status "$EXPECTED_FAILURE"
assert_stderr_contains 'unexpected asset'
rm -f "$github_state/assets/unexpected.txt"

printf '%s\n' 'corrupt release bytes' >"$github_state/assets/Timestamp-Only-0.1.0.dmg"
run_command env PATH="$test_path" "$fixture_repository/scripts/release" publish
assert_status "$EXPECTED_FAILURE"
assert_stderr_contains 'downloaded DMG differs'

run_command env PATH="$test_path" "$fixture_repository/scripts/version" -b2 -- 0.2.0
assert_status "$EXPECTED_SUCCESS"
[ "$(sed -n '1p' "$fixture_repository/VERSION")" = '0.2.0' ] || fail 'version command did not update VERSION'
[ "$(sed -n '1p' "$fixture_repository/BUILD_NUMBER")" = '2' ] || fail 'version command did not update BUILD_NUMBER'
if git -C "$fixture_repository" show-ref --verify --quiet refs/tags/v0.2.0; then
    fail 'version command created a tag'
fi

run_command env PATH="$test_path" "$fixture_repository/scripts/version" 0.1.0
assert_status "$EXPECTED_USAGE"
assert_stderr_contains 'must not be lower'

git -C "$fixture_repository" add VERSION BUILD_NUMBER
git -C "$fixture_repository" commit -m 'next fixture version' >/dev/null

failing_mv_bin="$test_directory/failing-mv-bin"
mkdir -p "$failing_mv_bin"
cat >"$failing_mv_bin/mv" <<'EOF'
#!/bin/bash

set -eu

destination=''
for argument in "$@"; do
    destination=$argument
done
if [ "$destination" = "$TEST_FAIL_MV_DESTINATION" ]; then
    printf '%s\n' 'simulated second move failure' >&2
    exit 1
fi
exec /bin/mv "$@"
EOF
chmod 755 "$failing_mv_bin/mv"

run_command env \
    PATH="$failing_mv_bin:$test_path" \
    TEST_FAIL_MV_DESTINATION="$fixture_repository/BUILD_NUMBER" \
    "$fixture_repository/scripts/version" --build-number 3 0.3.0
assert_status "$EXPECTED_FAILURE"
[ "$(sed -n '1p' "$fixture_repository/VERSION")" = '0.2.0' ] || fail 'VERSION was not restored after a partial replacement'
[ "$(sed -n '1p' "$fixture_repository/BUILD_NUMBER")" = '2' ] || fail 'BUILD_NUMBER was not restored after a partial replacement'

run_command env \
    PATH="$test_path" \
    TEST_MAKE_DIRTY=1 \
    "$fixture_repository/scripts/version" --build-number 3 0.3.0
assert_status "$EXPECTED_USAGE"
assert_stderr_contains 'working tree changed while release source checks were running'
[ "$(sed -n '1p' "$fixture_repository/VERSION")" = '0.2.0' ] || fail 'VERSION changed after source-check drift'
[ "$(sed -n '1p' "$fixture_repository/BUILD_NUMBER")" = '2' ] || fail 'BUILD_NUMBER changed after source-check drift'

printf '%s\n' 'Release command-line tests passed'
