;; The milestone for the bootstrap chain: a C program compiled inside
;; a sandbox containing nothing but the assembled bootstrap rootfs --
;; no Alpine, no host toolchain, no apk-installed anything. Its build
;; environment is another derivation's output, which is what
;; (root (derivation ...)) exists for.
;;
;; Deliberately trivial C. What is being tested is the toolchain and
;; the chain that produced it, not the program.
(derivation
 (name "bootstrap-hello")
 (build-environment (root (derivation "bootstrap-rootfs.derivation.scm")))
 (script
  "set -e\n"
  "mkdir -p out\n"
  "cat > hello.c <<'EOF'\n"
  "#include <stdio.h>\n"
  "int main(void) { printf(\"hello from the bootstrap toolchain\\n\"); return 0; }\n"
  "EOF\n"
  "gcc -static -O2 -o out/hello hello.c\n")
 (output "out"))
