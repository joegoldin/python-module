{
  description = ''
    A garnix module for projects using Python.

    Build a Python environment with your declared dependencies, run `pytest`, lint with `ruff`, and optionally deploy a web server.

    [Source](https://github.com/joegoldin/python-module).
  '';

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  inputs.garnix-lib.url = "github:joegoldin/garnix-lib";
  inputs.garnix-lib.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    { self, nixpkgs, garnix-lib }:
    {
      garnixModules.default =
        {
          pkgs,
          lib,
          config,
          ...
        }:
        let
          webServerSubmodule.options = {
            command =
              lib.mkOption {
                type = lib.types.nonEmptyStr;
                description = "The command to run to start the server in production.";
                example = "python -m myapp --port \"$PORT\"";
              }
              // {
                name = "server command";
              };

            port = lib.mkOption {
              type = lib.types.port;
              description = "Port to forward incoming HTTP requests to. The server command has to listen on this port. This also sets the PORT environment variable for the server command.";
              default = 8000;
            };

            path =
              lib.mkOption {
                type = lib.types.nonEmptyStr;
                description = "Path your Python server will be hosted on.";
                default = "/";
              }
              // {
                name = "API path";
              };
          };

          pythonSubmodule.options = {
            src =
              lib.mkOption {
                type = lib.types.path;
                description = "A path to the directory containing your Python sources (and, optionally, `requirements.txt`/`pyproject.toml`).";
                example = "./.";
              }
              // {
                name = "source directory";
              };

            pythonVersion =
              lib.mkOption {
                type = lib.types.str;
                description = "The Python version to build with (maps to nixpkgs `python<major><minor>`, falling back to `python3`).";
                default = "3.12";
                example = "3.11";
              }
              // {
                name = "Python version";
              };

            packageManager =
              lib.mkOption {
                type = lib.types.enum [ "requirements" "uv" "poetry" ];
                description = ''
                  The package manager to make available in the devshell. `requirements` uses a
                  plain pip-style workflow; `uv` and `poetry` add those tools. For fully reproducible
                  builds of third-party dependencies, resolve them into nixpkgs attribute names via
                  the `dependencies` option, or wire up `uv2nix`/`poetry2nix` in a consuming flake.
                '';
                default = "requirements";
              }
              // {
                name = "package manager";
              };

            dependencies = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "nixpkgs Python package attribute names to include in the built environment (e.g. `\"requests\"`, `\"flask\"`).";
              default = [ ];
              example = [ "requests" "flask" ];
            };

            pytest = lib.mkOption {
              type = lib.types.bool;
              description = "Whether to create a CI check that runs `pytest`.";
              default = true;
            };

            ruff = lib.mkOption {
              type = lib.types.bool;
              description = "Whether to create a CI check that runs `ruff check`.";
              default = true;
            };

            webServer = lib.mkOption {
              type = lib.types.nullOr (lib.types.submodule webServerSubmodule);
              description = "Whether to build a server configuration based on this project and deploy it to the garnix cloud.";
              default = null;
            };

            devTools =
              lib.mkOption {
                type = lib.types.listOf lib.types.package;
                description = "A list of packages to make available in the devshell for this project. This is useful for things like LSPs, formatters, etc.";
                default = [ ];
              }
              // {
                name = "development tools";
              };

            buildDependencies = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              description = "A list of additional (non-Python) dependencies required to build this package. They are made available in the devshell, and at build time.";
              default = [ ];
            };

            runtimeDependencies = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              description = "A list of dependencies required at runtime. They are made available in the devshell, at build time, and are available on the server at runtime.";
              default = [ ];
            };
          };

          pythonFor =
            projectConfig:
            let
              attr = "python" + builtins.replaceStrings [ "." ] [ "" ] projectConfig.pythonVersion;
            in
            pkgs.${attr} or pkgs.python3;

          runtimeEnvFor =
            projectConfig:
            (pythonFor projectConfig).withPackages (ps: map (name: ps.${name}) projectConfig.dependencies);

          testEnvFor =
            projectConfig:
            (pythonFor projectConfig).withPackages (
              ps: (map (name: ps.${name}) projectConfig.dependencies) ++ lib.optional projectConfig.pytest ps.pytest
            );

          managerToolsFor =
            projectConfig:
            if projectConfig.packageManager == "uv" then
              [ pkgs.uv ]
            else if projectConfig.packageManager == "poetry" then
              [ pkgs.poetry ]
            else
              [ ];
        in
        {
          options = {
            python = lib.mkOption {
              type = lib.types.attrsOf (lib.types.submodule pythonSubmodule);
              description = "An attrset of Python projects to generate.";
            };
          };

          config = {
            packages = builtins.mapAttrs (name: projectConfig: runtimeEnvFor projectConfig) config.python;

            checks = lib.foldlAttrs (
              acc: name: projectConfig:
              acc
              // lib.optionalAttrs projectConfig.pytest {
                "${name}-pytest" =
                  pkgs.runCommand "${name}-pytest"
                    {
                      nativeBuildInputs = [ (testEnvFor projectConfig) ];
                    }
                    ''
                      cp -r ${projectConfig.src}/. .
                      chmod -R u+w .
                      python -m pytest
                      mkdir "$out"
                    '';
              }
              // lib.optionalAttrs projectConfig.ruff {
                "${name}-ruff" =
                  pkgs.runCommand "${name}-ruff"
                    {
                      nativeBuildInputs = [ pkgs.ruff ];
                    }
                    ''
                      ruff check ${projectConfig.src}
                      mkdir "$out"
                    '';
              }
            ) { } config.python;

            devShells = builtins.mapAttrs (
              name: projectConfig:
              pkgs.mkShell {
                packages = [
                  (testEnvFor projectConfig)
                ]
                ++ lib.optional projectConfig.ruff pkgs.ruff
                ++ managerToolsFor projectConfig
                ++ projectConfig.devTools
                ++ projectConfig.buildDependencies
                ++ projectConfig.runtimeDependencies;
              }
            ) config.python;

            nixosConfigurations =
              let
                hasAnyWebServer = builtins.any (projectConfig: projectConfig.webServer != null) (
                  builtins.attrValues config.python
                );
              in
              lib.mkIf hasAnyWebServer {
                default =
                  [
                    {
                      services.nginx = {
                        enable = true;
                        recommendedProxySettings = true;
                        recommendedOptimisation = true;
                        virtualHosts.default = {
                          default = true;
                        };
                      };

                      networking.firewall.allowedTCPPorts = [ 80 ];
                    }
                  ]
                  ++ (builtins.attrValues (
                    builtins.mapAttrs (
                      name: projectConfig:
                      lib.mkIf (projectConfig.webServer != null) {
                        environment.systemPackages = [ config.packages.${name} ] ++ projectConfig.runtimeDependencies;

                        systemd.services.${name} = {
                          description = "${name} Python garnix module";
                          wantedBy = [ "multi-user.target" ];
                          after = [ "network-online.target" ];
                          wants = [ "network-online.target" ];
                          environment.PORT = toString projectConfig.webServer.port;
                          serviceConfig = {
                            Type = "simple";
                            DynamicUser = true;
                            WorkingDirectory = "${projectConfig.src}";
                            ExecStart = lib.getExe (
                              pkgs.writeShellApplication {
                                name = "start-${name}";
                                runtimeInputs = [ config.packages.${name} ] ++ projectConfig.runtimeDependencies;
                                text = projectConfig.webServer.command;
                              }
                            );
                          };
                        };

                        services.nginx.virtualHosts.default.locations.${projectConfig.webServer.path}.proxyPass =
                          "http://localhost:${toString projectConfig.webServer.port}";
                      }
                    ) config.python
                  ));
              };
          };
        };

      # Example wiring, used to verify the module evaluates end-to-end via
      # garnix-lib's `mkModules`. Not built by garnix CI (only `packages`,
      # `checks`, `devShells` and `nixosConfigurations` are).
      lib.exampleFlakeOutputs = garnix-lib.lib.mkModules {
        modules = [ self.garnixModules.default ];
        config = {
          python.example.src = ./example;
        };
      };
    };
}
