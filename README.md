# python-module

A [garnix](https://garnix.io) module for projects using Python.

It builds a Python environment with your declared dependencies, runs `pytest`,
lints with `ruff`, and can optionally deploy a web server.

## Usage

In your project's `flake.nix`, consume the module through
[`garnix-lib`](https://github.com/joegoldin/garnix-lib)'s `mkModules`:

```nix
{
  inputs.garnix-lib.url = "github:joegoldin/garnix-lib";
  inputs.python-module.url = "github:joegoldin/python-module";

  outputs = { garnix-lib, python-module, ... }:
    garnix-lib.lib.mkModules {
      modules = [ python-module.garnixModules.default ];
      config = {
        python.myapp = {
          src = ./.;
          # pythonVersion = "3.12";
          # packageManager = "uv";
          # dependencies = [ "requests" "flask" ];  # nixpkgs attr names
        };
      };
    };
}
```

This produces:

- `packages.<system>.myapp` — a Python interpreter environment with your
  declared `dependencies`.
- `checks.<system>.myapp-pytest` — runs `python -m pytest` over your sources.
- `checks.<system>.myapp-ruff` — runs `ruff check`.
- `devShells.<system>.myapp` — the interpreter, `pytest`, `ruff`, and your
  chosen package manager (`uv`/`poetry`).

### Options

| Option | Default | Description |
| --- | --- | --- |
| `src` | (required) | Directory containing your Python sources. |
| `pythonVersion` | `"3.12"` | nixpkgs `python<major><minor>`. |
| `packageManager` | `"requirements"` | `requirements` \| `uv` \| `poetry` (devshell tooling). |
| `dependencies` | `[ ]` | nixpkgs Python package attr names to install. |
| `pytest` | `true` | Create a `pytest` check. |
| `ruff` | `true` | Create a `ruff check` check. |
| `webServer` | `null` | Deploy a systemd + nginx web server (garnix hosting). |
| `devTools` / `buildDependencies` / `runtimeDependencies` | `[ ]` | Extra packages. |

### Reproducible third-party dependencies

The `dependencies` option pulls packages straight from nixpkgs. For lockfile-driven
reproducibility of PyPI dependencies, resolve them with
[`uv2nix`](https://github.com/pyproject-nix/uv2nix) or
[`poetry2nix`](https://github.com/nix-community/poetry2nix) in your consuming flake
and pass the resulting environment through `buildDependencies`/`runtimeDependencies`.

An evaluable `example/` project is included; see `.#lib.exampleFlakeOutputs`.
