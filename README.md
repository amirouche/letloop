# [`letloop`](https://github.com/amirouche/letloop)

[![Continuous Integration](https://github.com/amirouche/letloop/actions/workflows/continuous-integration.yaml/badge.svg)](https://github.com/amirouche/letloop/actions/workflows/continuous-integration.yaml)

See `letloop.md`:

## Getting started

```shell
sudo apt install chezscheme
git clone https://github.com/amirouche/letloop
cd letloop
scheme --program letloop.scm compile /usr/lib/csv9.5.4/ta6le/ letloop.scm letloop
cp letloop $HOME/.local/bin/
export PATH="$HOME/.local/bin/:$PATH"
```

## [Contact](mailto:amirouche@hyper.dev)
