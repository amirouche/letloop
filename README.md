# letloop

```
  ___       ___       ___       ___       ___       ___
 /\  \     /\  \     /\  \     /\__\     /\  \     /\  \
 \:\  \   /::\  \    \:\  \   /:/  /    /::\  \   /::\  \
 /::\__\ /::\:\__\   /::\__\ /:/__/    /:/\:\__\ /::\:\__\
/:/\/__/ \/\::/  /  /:/\/__/ \:\  \    \:\/:/  / \;:::/  /
\/__/      /:/  /   \/__/     \:\__\    \::/  /   |:\/__/
           \/__/               \/__/     \/__/     \|__|
```

**Getting started**

Requires `uuid` headers for using `letloop compile`.

```shell
./venv
make chezscheme
make letloop
mv a.out local/bin/letloop
make check
```

## Development Skills

This project includes Claude Code skills for common development tasks:

- **`/letloop-build-chez`** - Build ChezScheme from source
- **`/letloop-build`** - Build the letloop binary
- **`/letloop-install`** - Build and install letloop to local/bin
- **`/letloop-full-setup`** - Complete setup from scratch
- **`/letloop-test`** - Run the complete test suite
- **`/letloop-clean`** - Clean temporary files

Use these skills with Claude Code by invoking them with slash commands or natural language requests like "run the tests" or "build letloop".

See [.claude/SKILLS.md](.claude/SKILLS.md) for detailed documentation.
