{ pkgs, ... }:
{
  packages = [
    pkgs.git
    pkgs.flutter
  ];

  languages = {
    javascript = {
      enable = true;
      package = pkgs.nodejs_22;
      pnpm = {
        enable = true;
        install.enable = true;
      };
    };

    typescript.enable = true;

    dart.enable = true;
  };

  scripts = {
    dev = {
      exec = "pnpm dev";
      description = "Start web app and Convex dev servers in parallel";
    };
    typecheck = {
      exec = "pnpm run typecheck";
      description = "Type-check all TypeScript packages";
    };
    format = {
      exec = "pnpm run format";
      description = "Format all code with Biome";
    };
    lint = {
      exec = "pnpm --filter web run lint";
      description = "Lint web app with ESLint";
    };
  };

  git-hooks.hooks = {
    check-merge-conflicts.enable = true;
    detect-private-keys.enable = true;
  };
}
