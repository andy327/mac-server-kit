# shellcheck shell=bash
# key=value parsing and writing (lib/common.sh)

kvfile() { F=$TEST_TMP/f.conf; printf '%s\n' "$@" >"$F"; }

test_get_plain_value() {
    load_libs; kvfile 'A=hello'
    assert_eq hello "$(kv_get "$F" A)"
}

test_get_strips_inline_comment_and_whitespace() {
    load_libs; kvfile 'A=  v1.41   # reason, 2026-11' '  B=x'
    assert_eq v1.41 "$(kv_get "$F" A)"
    assert_eq x "$(kv_get "$F" B)"
}

test_get_hash_without_space_is_kept() {
    load_libs; kvfile 'A=abc#def'
    assert_eq 'abc#def' "$(kv_get "$F" A)"
}

# shellcheck disable=SC2016  # the $HOME and backticks must stay literal
test_get_quoted_value_is_literal() {
    load_libs; kvfile 'A="pa ss # word $HOME `x`"  # comment' 'B="with "inner" quotes"'
    assert_eq 'pa ss # word $HOME `x`' "$(kv_get "$F" A)"
    assert_eq 'with "inner" quotes' "$(kv_get "$F" B)"
}

test_get_empty_and_comment_only() {
    load_libs; kvfile 'A=' 'B=   # nothing' 'C=""'
    assert_ok kv_has "$F" A
    assert_eq '' "$(kv_get "$F" A)"
    assert_eq '' "$(kv_get "$F" B)"
    assert_eq '' "$(kv_get "$F" C)"
}

test_get_missing_key_fails() {
    load_libs; kvfile '#A=commented' 'AB=prefix'
    assert_fails kv_get "$F" A
    assert_fails kv_get "$TEST_TMP/nope" A
}

test_get_last_line_wins() {
    load_libs; kvfile 'A=1' 'A=2'
    assert_eq 2 "$(kv_get "$F" A)"
}

test_get_key_with_dash() {
    load_libs; kvfile 'HOLD_tracearr-db=pg18 # migration, 2026-11'
    assert_eq pg18 "$(kv_get "$F" HOLD_tracearr-db)"
    assert_eq 'migration, 2026-11' "$(kv_comment "$F" HOLD_tracearr-db)"
}

test_comment_after_quoted_value() {
    load_libs; kvfile 'A="x # y" # the reason'
    assert_eq 'the reason' "$(kv_comment "$F" A)"
}

test_append_adds_missing_key_only() {
    load_libs; kvfile '# header' 'A=1'
    kv_append "$F" A 2
    kv_append "$F" B 3
    assert_eq '# header
A=1
B=3' "$(cat "$F")"
}

test_append_fixes_missing_final_newline() {
    load_libs; F=$TEST_TMP/f.conf; printf 'A=1' >"$F"
    kv_append "$F" B 2
    assert_eq 'A=1
B=2' "$(cat "$F")"
}

test_append_quotes_when_needed_and_round_trips() {
    load_libs; kvfile ''
    kv_append "$F" S 'has # hash'
    kv_append "$F" T 'plain' quote
    kv_append "$F" U ' lead'
    assert_eq 'has # hash' "$(kv_get "$F" S)"
    assert_eq 'plain' "$(kv_get "$F" T)"
    assert_eq ' lead' "$(kv_get "$F" U)"
    assert_contains "$(cat "$F")" 'T="plain"'
}

test_append_rejects_newlines_and_bad_keys() {
    load_libs; kvfile ''
    assert_fails kv_append "$F" A $'two\nlines'
    assert_fails kv_append "$F" 'BAD KEY' x
}

test_replace_keeps_other_lines_and_mode() {
    load_libs; kvfile '# top' 'MODULES=a' 'X=1 # keep' 'MODULES=old'
    chmod 600 "$F"
    kv_replace "$F" MODULES 'a b'
    assert_eq '# top
MODULES=a b
X=1 # keep' "$(cat "$F")"
    assert_eq 600 "$(stat -f %Lp "$F")"
}

test_replace_appends_when_missing() {
    load_libs; kvfile 'X=1'
    kv_replace "$F" MODULES 'romm'
    assert_eq 'romm' "$(kv_get "$F" MODULES)"
}

test_keys_lists_each_key_once() {
    load_libs; kvfile 'A=1' '# B=2' 'C=3' 'A=4'
    assert_eq 'A C' "$(kv_keys "$F" | tr '\n' ' ' | sed 's/ $//')"
}

test_lists() {
    load_libs
    assert_eq 'a b' "$(list_add 'a b' b)"
    assert_eq 'a b c' "$(list_add 'a b' c)"
    assert_eq 'x' "$(list_add '' x)"
    assert_ok in_list b 'a b c'
    assert_fails in_list ab 'a b c'
}

test_vers_ge() {
    load_libs
    assert_ok vers_ge 2.24.1 2.24
    assert_ok vers_ge 2.30 2.24
    assert_ok vers_ge 10.0 9.9
    assert_fails vers_ge 2.9 2.24
}
