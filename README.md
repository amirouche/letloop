# binink

```
 .o8        o8o               o8o              oooo        
"888        `"'               `"'              `888        
 888oooo.  oooo  ooo. .oo.   oooo  ooo. .oo.    888  oooo  
 d88' `88b `888  `888P"Y88b  `888  `888P"Y88b   888 .8P'   
 888   888  888   888   888   888   888   888   888888.    
 888   888  888   888   888   888   888   888   888 `88b.  
 `Y8bod8P' o888o o888o o888o o888o o888o o888o o888o o888o 
```

**Getting started**

Requires `zlib`, `lz4`, and `uuid` headers for using `binink compile`.

```shell
./venv
make chezscheme
make binink
mv a.out local/bin/binink
make check
```

## Development Skills

This project includes Claude Code skills for common development tasks:

- **`/binink-build-chez`** - Build ChezScheme from source
- **`/binink-build`** - Build the binink binary
- **`/binink-install`** - Build and install binink to local/bin
- **`/binink-full-setup`** - Complete setup from scratch
- **`/binink-test`** - Run the complete test suite
- **`/binink-clean`** - Clean temporary files

Use these skills with Claude Code by invoking them with slash commands or natural language requests like "run the tests" or "build binink".

See [.claude/SKILLS.md](.claude/SKILLS.md) for detailed documentation.
