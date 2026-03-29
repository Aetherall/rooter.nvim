{
  description = "rooter.nvim — project root detection and VS Code workspace compatibility for Neovim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        mini-nvim = pkgs.fetchFromGitHub {
          owner = "echasnovski";
          repo = "mini.nvim";
          rev = "main";
          hash = "sha256-ebqTqBKQ2l5s+UKn9tBbVQcY5uFidR5JUNQKyYjdV+o=";
        };

        rooter-nvim = pkgs.vimUtils.buildVimPlugin {
          pname = "rooter.nvim";
          version = "0.1.0";
          src = self;
        };

      in {
        packages.default = rooter-nvim;

        checks.default = pkgs.stdenvNoCC.mkDerivation {
          name = "rooter-nvim-tests";
          src = self;
          nativeBuildInputs = [ pkgs.neovim ];
          buildPhase = ''
            export HOME=$TMPDIR
            mkdir -p deps
            ln -s ${mini-nvim} deps/mini.nvim
            nvim --headless -u tests/minimal_init.lua -c "lua MiniTest.run()" 2>&1 | tee test-output.txt
            if grep -q "FAIL" test-output.txt; then
              echo "Tests failed!"
              exit 1
            fi
          '';
          installPhase = "mkdir -p $out && cp test-output.txt $out/";
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [ pkgs.neovim ];
        };
      }
    );
}
