# Generate tiny compiled binary for wrapping executables

## Getting started
Make sure you are using bash. The script will not behave correctly if you are using zsh (or other shell variants).

```sh
# Loads the binary wrapper functions so they can be used from the command line
$ source make-binary-wrapper.sh

# Generate binary for Python which injects an environment variable
$ makeBinaryWrapper /usr/bin/python3 ./wrapper --set "MESSAGE" "WORLD WORLD"

$ ./wrapper -c "import os; print(os.getenv('MESSAGE'))"
HELLO WORLD
```

## Motivation
[bash-wrappers](https://github.com/NixOS/nixpkgs/blob/1d6428140194b5bac68266ca11a441ed6f63571c/pkgs/build-support/setup-hooks/make-wrapper.sh) can be used to inject custom environment variables into executables. In the cases where this executable is an interpreter (like Python or Perl), it can be placed in the shebang line of a script. On MacOS, you can't put a script (with its own shebang) in the shebang line of an executable [due to a limitation with the `execve`-syscall](https://stackoverflow.com/questions/67100831/macos-shebang-with-absolute-path-not-working). 

In order to create a cross-platform solution to this problem, we could generate some kind of tiny compiled binary that could be substituted in for the bash wrappers. Then this would work on both Linux and MacOS. See https://github.com/NixOS/nixpkgs/issues/23018 for more discussion.

This implementation uses bash to generate C-code according to the same interface as the bash wrappers in Nix, and compiles it. The result is a binary executable (typically around 14kB in size), which can be referenced in the shebang line of a script on both MacOS and Linux.



### Dependencies
- `bash`
- A C-compiler: `gcc` on Linux or `clang` on MacOS
- [`unistd`](https://pubs.opengroup.org/onlinepubs/009695399/basedefs/unistd.h.html) + [`stdlib`](https://pubs.opengroup.org/onlinepubs/009695399/basedefs/stdlib.h.html) (C libraries)


*A focus in this implementation has been to minimize the number of dependencies - and also keep the implementation itself as minimal as possible.*

## Consider the following wrapper shell script:
```sh
#! /nix/store/ra8yvijdfjcs5f66b99gdjn86gparrbz-bash-4.4-p23/bin/bash -e
export NIX_PYTHONPREFIX='/nix/store/i46k148mi830riq4wxh49ki8qmq0731k-python3-3.9.2-env'
export NIX_PYTHONEXECUTABLE='/nix/store/i46k148mi830riq4wxh49ki8qmq0731k-python3-3.9.2-env/bin/python3.9'
export NIX_PYTHONPATH='/nix/store/i46k148mi830riq4wxh49ki8qmq0731k-python3-3.9.2-env/lib/python3.9/site-packages'
export PYTHONNOUSERSITE='true'
exec "/nix/store/7pjbbmnrch7frgyp7gz19ay0z1173c7y-python3-3.9.2/bin/python"  "$@"
```
Putting this script in a shebang works fine on Linux, but doesn't work on MacOS. If we want to write C-code that replaces it (and works on MacOS+Linux), we can do it like this in C:
```c
#include <unistd.h>
#include <stdlib.h>

int main(int argc, char** argv) {
    putenv("NIX_PYTHONPREFIX=/nix/store/i46k148mi830riq4wxh49ki8qmq0731k-python3-3.9.2-env");
    putenv("NIX_PYTHONEXECUTABLE=/nix/store/i46k148mi830riq4wxh49ki8qmq0731k-python3-3.9.2-env/bin/python3.9");
    putenv("NIX_PYTHONPATH=/nix/store/i46k148mi830riq4wxh49ki8qmq0731k-python3-3.9.2-env/lib/python3.9/site-packages");
    putenv("PYTHONNOUSERSITE=true");
    argv[0] = "/nix/store/7pjbbmnrch7frgyp7gz19ay0z1173c7y-python3-3.9.2/bin/python";
    return execv(argv[0], argv);
}
```

This proof of concept creates a simple bash function that generates C-code for such a tiny compiled binary (and compiles it), with an interface similar to the existing [makeWrapper in Nix](https://github.com/NixOS/nixpkgs/blob/1d6428140194b5bac68266ca11a441ed6f63571c/pkgs/build-support/setup-hooks/make-wrapper.sh). There are some features of the original makeWrapper which is not yet implemented here.

### Debuggability

A big concern with using a binary wrapper is that people can't just open up the file to see what it is doing when debugging their own problems. This is fixed by embedding the source code as a string variable into the source code itself (code-ception). The result is that the binary file will contain the source code in human readable format when opening the file in a plain text editor or using the `strings` command on MacOS or Linux.

Example of how it looks right now:
```sh
makeBinaryWrapper /usr/bin/python3 ./wrapper \
  --set HELLO WORLD --set-default X $'Y\n"' --unset Z --argv0 python3

cat ./wrapper
```

```c
...binary-data...
----------
// This binary wrapper was compiled from the following generated C-code:
#include <unistd.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    putenv("HELLO=WORLD");
    setenv("X", "Y\n\"", 0);
    unsetenv("Z");
    argv[0] = "python3";
    return execv("/usr/bin/python3", argv);
}
----------
...binary-data...
```

C String literals in the generated code (including the documentation) are properly escaped. I got some help with how to do this properly on StackOverflow: https://stackoverflow.com/questions/67710149/how-can-i-sanitize-user-input-into-valid-c-string-literals.

### Generated source code example
```sh
makeDocumentedCWrapper /usr/bin/python3 --set HELLO WORLD --set-default X $'Y\n"' --unset Z --argv0 python3
```
```c
#include <unistd.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    putenv("HELLO=WORLD");
    setenv("X", "Y\n\"", 0);
    unsetenv("Z");
    argv[0] = "python3";
    return execv("/usr/bin/python3", argv);
}

const char * SOURCE_CODE = "\n----------\n// This binary wrapper was compiled from the following generated C-code:\n#include <unistd.h>\n#include <stdlib.h>\n\nint main(int argc, char **argv) {\n    putenv(\"HELLO=WORLD\");\n    setenv(\"X\", \"Y\\n\\\"\", 0);\n    unsetenv(\"Z\");\n    argv[0] = \"python3\";\n    return execv(\"/usr/bin/python3\", argv);\n}\n----------\n";
```
