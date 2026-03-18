# letloop

```
                                                                
  ,,                  ,,                                        
`7MM           mm   `7MM                                        
  MM           MM     MM                                        
  MM  .gP"Ya mmMMmm   MM  ,pW"Wq.   ,pW"Wq.   ,pW"Wq.`7MMpdMAo. 
  MM ,M'   Yb  MM     MM 6W'   `Wb 6W'   `Wb 6W'   `Wb MM   `Wb 
  MM 8M""""""  MM     MM 8M     M8 8M     M8 8M     M8 MM    M8 
  MM YM.    ,  MM     MM YA.   ,A9 YA.   ,A9 YA.   ,A9 MM   ,AP 
.JMML.`Mbmmd'  `Mbmo.JMML.`Ybmd9'   `Ybmd9'   `Ybmd9'  MMbmmd'  
                                                       MM       
                                                     .JMML.     
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
