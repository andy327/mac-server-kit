# shellcheck shell=bash
# tests/check-private finds machine-specific data and nothing else

private_check() {   # content... -> runs check-private on a file holding these lines
    local f=$TEST_TMP/sample.txt
    printf '%s\n' "$@" >"$f"
    CI=1 KIT_PRIVATE_WORDS=$TEST_TMP/words "$TEST_ROOT/tests/check-private" "$f"
}

test_clean_file_passes() {
    assert_ok private_check 'MEDIA_ROOT=~/Media' 'https://<name>.<your-tailnet>.ts.net' '/Users/<you>/Media' \
        'Co-Authored-By: Claude <noreply@anthropic.com>' 'sha256:4af0c804003481e100180e1f8d4d5e9c48163fedc0f88d061881b615aef9d183'
}

test_finds_each_kind() {
    local samples hit
    samples=$TEST_TMP/samples
    {
        echo 'TS_AUTHKEY=tskey-auth-k1234567CNTRL-abc'                  # check-private: allow
        echo 'https://myhost.tail1234.ts.net'                           # check-private: allow
        echo 'https://hc-ping.com/12345678-aaaa-4bbb-8ccc-1234567890ab' # check-private: allow
        echo '/Users/someone/server'                                    # check-private: allow
        echo 'mail me: someone@example.com'                             # check-private: allow
        echo "PrivateKey = $(printf 'A%.0s' $(seq 43))="
    } >"$samples"
    while IFS= read -r hit; do
        if private_check "$hit" >/dev/null 2>&1; then fail "missed: $hit"; fi
    done <"$samples"
}

test_allowed_parts_do_not_hide_real_hits() {
    if private_check 'noreply@anthropic.com and someone@example.com' >/dev/null 2>&1; then  # check-private: allow
        fail "a real address next to an allowed one was missed"
    fi
}

test_marker_allows_a_line_and_reports_true_line_numbers() {
    local out
    out=$(private_check 'x # check-private: allow someone@example.com' 'fine' '/Users/real/path' 2>&1) && fail "should fail"  # check-private: allow
    assert_contains "$out" 'sample.txt:3:/Users/real/path'  # check-private: allow
    assert_not_contains "$out" 'example.com'
}

test_local_words_file() {
    printf '# machine names\nGizmo\n' >"$TEST_TMP/words"
    assert_fails private_check 'backups from gizmo'
    assert_ok private_check 'nothing here'
}
