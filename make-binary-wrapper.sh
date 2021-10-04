# Generate a binary executable wrapper for wrapping an executable.
# The binary is compiled from generated C-code using gcc.
# makeBinaryWrapper EXECUTABLE OUT_PATH ARGS

# ARGS:
# --argv0       NAME    : set name of executed process to NAME
#                         (otherwise it’s called …-wrapped)
# --set         VAR VAL : add VAR with value VAL to the executable’s
#                         environment
# --set-default VAR VAL : like --set, but only adds VAR if not already set in
#                         the environment
# --unset       VAR     : remove VAR from the environment
# --add-flags   FLAGS   : add FLAGS to invocation of executable

# --prefix          ENV SEP VAL   : suffix/prefix ENV with VAL, separated by SEP
# --suffix

# To troubleshoot a binary wrapper after you compiled it,
# use the `strings` command or open the binary file in a text editor.
makeBinaryWrapper() {
    makeDocumentedCWrapper "$1" "${@:3}" | gcc -Os -x c -o "$2" -
}

# Generate source code for the wrapper in such a way that the wrapper source code
# will still be readable even after compilation
# makeDocumentedCWrapper EXECUTABLE ARGS
# ARGS: same as makeBinaryWrapper
makeDocumentedCWrapper() {
    local src docs
    src=$(makeCWrapper "$@")
    docs=$(documentationString "$src")
    printf '%s\n\n' "$src"
    printf '%s\n' "$docs"
}

# makeCWrapper EXECUTABLE ARGS
# ARGS: same as makeBinaryWrapper
makeCWrapper() {
    local argv0 n params cmd main flagsBefore flags executable params length
    local uses_prefix uses_suffix uses_concat3
    executable=$(escapeStringLiteral "$1")
    params=("$@")
    length=${#params[*]}
    for ((n = 1; n < length; n += 1)); do
        p="${params[n]}"
        case $p in
            --set)
                cmd=$(setEnv "${params[n + 1]}" "${params[n + 2]}")
                main="$main    $cmd"$'\n'
                n=$((n + 2))
                [ $n -ge "$length" ] && main="$main    #error makeCWrapper: $p takes 2 arguments"$'\n'
            ;;
            --set-default)
                cmd=$(setDefaultEnv "${params[n + 1]}" "${params[n + 2]}")
                main="$main    $cmd"$'\n'
                n=$((n + 2))
                [ $n -ge "$length" ] && main="$main    #error makeCWrapper: $p takes 2 arguments"$'\n'
            ;;
            --unset)
                cmd=$(unsetEnv "${params[n + 1]}")
                main="$main    $cmd"$'\n'
                n=$((n + 1))
                [ $n -ge "$length" ] && main="$main    #error makeCWrapper: $p takes 1 argument"$'\n'
            ;;
            --prefix)
                cmd=$(setEnvPrefix "${params[n + 1]}" "${params[n + 2]}" "${params[n + 3]}")
                main="$main    $cmd"$'\n'
                uses_prefix=1
                uses_concat3=1
                n=$((n + 3))
                [ $n -ge "$length" ] && main="$main    #error makeCWrapper: $p takes 3 arguments"$'\n'
            ;;
            --suffix)
                cmd=$(setEnvSuffix "${params[n + 1]}" "${params[n + 2]}" "${params[n + 3]}")
                main="$main    $cmd"$'\n'
                uses_suffix=1
                uses_concat3=1
                n=$((n + 3))
                [ $n -ge "$length" ] && main="$main    #error makeCWrapper: $p takes 3 arguments"$'\n'
            ;;
            --add-flags)
                flags="${params[n + 1]}"
                flagsBefore="$flagsBefore $flags"
                n=$((n + 1))
                [ $n -ge "$length" ] && main="$main    #error makeCWrapper: $p takes 1 argument"$'\n'
            ;;
            --argv0)
                argv0=$(escapeStringLiteral "${params[n + 1]}")
                n=$((n + 1))
                [ $n -ge "$length" ] && main="$main    #error makeCWrapper: $p takes 1 argument"$'\n'
            ;;
            *) # Using an error macro, we will make sure the compiler gives an understandable error message
                main="$main    #error makeCWrapper: Uknown argument ${p}"$'\n'
            ;;
        esac
    done
    # shellcheck disable=SC2086
    [ -z "$flagsBefore" ] || main="$main"${main:+$'\n'}$(addFlags $flagsBefore)$'\n'$'\n'
    main="$main    argv[0] = \"${argv0:-${executable}}\";"$'\n'
    main="$main    return execv(\"${executable}\", argv);"$'\n'

    printf '%s\n' "#include <unistd.h>"
    printf '%s\n' "#include <stdlib.h>"
    [ -z "$uses_concat3" ] || printf '%s\n' "#include <string.h>"
    [ -z "$uses_concat3" ] || printf '\n%s\n' "$(concat3Fn)"
    [ -z "$uses_prefix" ]  || printf '\n%s\n' "$(setEnvPrefixFn)"
    [ -z "$uses_suffix" ]  || printf '\n%s\n' "$(setEnvSuffixFn)"
    printf '\n%s' "int main(int argc, char **argv) {"
    printf '\n%s' "$main"
    printf '%s\n' "}"
}

addFlags() {
    local result n flag flags var
    var="argv_tmp"
    flags=("$@")
    for ((n = 0; n < ${#flags[*]}; n += 1)); do
        flag=$(escapeStringLiteral "${flags[$n]}")
        result="$result    ${var}[$((n+1))] = \"$flag\";"$'\n'
    done
    printf '    %s\n' "char **$var = malloc(sizeof(*$var) * ($((n+1)) + argc));"
    printf '    %s\n' "${var}[0] = argv[0];"
    printf '%s' "$result"
    printf '    %s\n' "for (int i = 1; i < argc; ++i) {"
    printf '    %s\n' "    ${var}[$n + i] = argv[i];"
    printf '    %s\n' "}"
    printf '    %s\n' "${var}[$n + argc] = NULL;"
    printf '    %s\n' "argv = $var;"
}

# prefix ENV SEP VAL
setEnvPrefix() {
    local env sep val
    env=$(escapeStringLiteral "$1")
    sep=$(escapeStringLiteral "$2")
    val=$(escapeStringLiteral "$3")
    printf '%s' "set_env_prefix(\"$env\", \"$sep\", \"$val\");"
}

# suffix ENV SEP VAL
setEnvSuffix() {
    local env sep val
    env=$(escapeStringLiteral "$1")
    sep=$(escapeStringLiteral "$2")
    val=$(escapeStringLiteral "$3")
    printf '%s' "set_env_suffix(\"$env\", \"$sep\", \"$val\");"
}

# setEnv KEY VALUE
setEnv() {
    local key value
    key=$(escapeStringLiteral "$1")
    value=$(escapeStringLiteral "$2")
    printf '%s' "putenv(\"$key=$value\");"
}

# setDefaultEnv KEY VALUE
setDefaultEnv() {
    local key value
    key=$(escapeStringLiteral "$1")
    value=$(escapeStringLiteral "$2")
    printf '%s' "setenv(\"$key\", \"$value\", 0);"
}

# unsetEnv KEY
unsetEnv() {
    local key
    key=$(escapeStringLiteral "$1")
    printf '%s' "unsetenv(\"$key\");"
}

# Put the entire source code into const char* SOURCE_CODE to make it readable after compilation.
# documentationString SOURCE_CODE
documentationString() {
    local docs
    docs=$(escapeStringLiteral $'\n----------\n// This binary wrapper was compiled from the following generated C-code:\n'"$1"$'\n----------\n')
    printf '%s' "const char * SOURCE_CODE = \"$docs\";"
}

# Makes it safe to insert STRING within quotes in a C String Literal.
# escapeStringLiteral STRING
escapeStringLiteral() {
    local result
    result=${1//$'\\'/$'\\\\'}
    result=${result//\"/'\"'}
    result=${result//$'\n'/"\n"}
    result=${result//$'\r'/"\r"}
    printf '%s' "$result"
}

concat3Fn() {
    printf '%s' "\
char *concat3(char *x, char *y, char *z) {
    int xn = strlen(x);
    int yn = strlen(y);
    int zn = strlen(z);
    char *res = malloc(sizeof(*res)*(xn + yn + zn + 1));
    strncpy(res, x, xn);
    strncpy(res + xn, y, yn);
    strncpy(res + xn + yn, z, zn);
    res[xn + yn + zn] = '\0';
    return res;
}
"
}

setEnvPrefixFn() {
    printf '%s' "\
void set_env_prefix(char *env, char *sep, char *val) {
    char *existing = getenv(env);
    if (existing) val = concat3(val, sep, existing);
    setenv(env, val, 1);
    if (existing) free(val);
}
"
}

setEnvSuffixFn() {
    printf '%s' "\
void set_env_suffix(char *env, char *sep, char *val) {
    char *existing = getenv(env);
    if (existing) val = concat3(existing, sep, val);
    setenv(env, val, 1);
    if (existing) free(val);
}
"
}
