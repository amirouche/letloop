#!/usr/bin/env python3
"""Emit a Scheme bytevector from a SPIR-V binary.

Usage:
    spv-to-scheme.py <path/to/foo.spv> <scheme-identifier>

Writes to stdout. Used by `make shaders` to refresh
src/letloop/desktop/shader.scm.
"""
import sys


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: spv-to-scheme.py PATH IDENT\n")
        sys.exit(2)
    path, ident = sys.argv[1], sys.argv[2]
    with open(path, "rb") as f:
        data = f.read()
    print(f"  ;; {len(data)} bytes from {path}")
    print(f"  (define {ident}")
    print("    (bytevector")
    chunk = []
    for b in data:
        chunk.append(f"#x{b:02x}")
        if len(chunk) == 12:
            print("     " + " ".join(chunk))
            chunk = []
    if chunk:
        print("     " + " ".join(chunk))
    print("    ))")
    print()


if __name__ == "__main__":
    main()
