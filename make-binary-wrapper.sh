# Generate a binary executable wrapper for wrapping an executable.
# The binary is compiled from generated C-code using gcc.
# makeBinaryWrapper EXECUTABLE OUT_PATH ARGS

# ARGS:
# --argv0       NAME    : set name of executed process to NAME
#                         (defaults to EXECUTABLE)
# --set         VAR VAL : add VAR with value VAL to the executable’s
#                         environment
# --set-default VAR VAL : like --set, but only adds VAR if not already set in
#                         the environment
# --unset       VAR     : remove VAR from the environment
#
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
    local src=$(makeCWrapper "$@")
    local docs=$(documentationString "$src")
    printf "%s\n" "$src"
    printf "\n%s\n" "$docs"
}

# makeCWrapper EXECUTABLE ARGS
# ARGS: same as makeBinaryWrapper
makeCWrapper() {
    local argv0 n params cmd
    local executable=$(escapeStringLiteral "$1")
    local params=("$@")

    printf "%s\n" "#include <unistd.h>"
    printf "%s\n" "#include <stdlib.h>"
    printf "\n%s\n" "int main(int argc, char **argv) {"

    for ((n = 1; n < ${#params[*]}; n += 1)); do
        p="${params[$n]}"
        if [[ "$p" == "--set" ]]; then
            cmd=$(setEnv "${params[$((n + 1))]}" "${params[$((n + 2))]}")
            n=$((n + 2))
            printf "%s\n" "    $cmd"
        elif [[ "$p" == "--set-default" ]]; then
            cmd=$(setDefaultEnv "${params[$((n + 1))]}" "${params[$((n + 2))]}")
            n=$((n + 2))
            printf "%s\n" "    $cmd"
        elif [[ "$p" == "--unset" ]]; then
            cmd=$(unsetEnv "${params[$((n + 1))]}")
            printf "%s\n" "    $cmd"
            n=$((n + 1))
        elif [[ "$p" == "--argv0" ]]; then
            argv0=$(escapeStringLiteral "${params[$((n + 1))]}")
            n=$((n + 1))
        else
            # Using an error macro, we will make sure the compiler gives an understandable error message
            printf "%s\n" "    #error makeCWrapper did not understand argument ${p}"
        fi
    done

    printf "%s\n" "    argv[0] = \"${argv0:-${executable}}\";"
    printf "%s\n" "    return execv(\"${executable}\", argv);"
    printf "%s\n" "}"
}

# setEnv KEY VALUE
setEnv() {
    local key=$(escapeStringLiteral "$1")
    local value=$(escapeStringLiteral "$2")
    printf "%s" "putenv(\"${key}=${value}\");"
}

# setDefaultEnv KEY VALUE
setDefaultEnv() {
    local key=$(escapeStringLiteral "$1")
    local value=$(escapeStringLiteral "$2")
    printf "%s" "setenv(\"$key\", \"$value\", 0);"
}

# unsetEnv KEY
unsetEnv() {
    local key=$(escapeStringLiteral "$1")
    printf "%s" "unsetenv(\"$key\");"
}

# Put the entire source code into const char* SOURCE_CODE to make it readable after compilation.
# documentationString SOURCE_CODE
documentationString() {
    local docs=$(escapeStringLiteral $'\n----------\n// This binary wrapper was compiled from the following generated C-code:\n'"$1"$'\n----------\n')
    printf "%s" "const char * SOURCE_CODE = \"$docs\";"
}

# Makes it safe to insert STRING within quotes in a C String Literal.
# escapeStringLiteral STRING
escapeStringLiteral() {
    local result
    result=${1//$'\\'/$'\\\\'}
    result=${result//\"/'\"'}
    result=${result//$'\n'/"\n"}
    result=${result//$'\r'/"\r"}
    printf "%s" "$result"
}

concat3Fn() {
    printf "%s\n" 'char *concat3(char *x, char *y, char *z) {'
    printf "%s\n" '    int xn = 0; while(x[++xn]);'
    printf "%s\n" '    int yn = 0; while(y[++yn]);'
    printf "%s\n" '    int zn = 0; while(z[++zn]);'
    printf "%s\n" '    char *res = malloc(sizeof(*res)*(xn + yn + zn + 1));'
    printf "%s\n" '    for (int i = 0; i < xn; ++i) res[i] = x[i];'
    printf "%s\n" '    for (int i = 0; i < yn; ++i) res[xn+i] = y[i];'
    printf "%s\n" '    for (int i = 0; i < zn; ++i) res[xn+yn+i] = z[i];'
    printf "%s\n" "    res[xn+yn+zn] = '\0';"
    printf "%s\n" '    return res;'
    printf "%s\n" '}'
}
