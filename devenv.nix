{ pkgs, ... }:
{
  packages = with pkgs; [
    git
    android-tools
    rustup
  ];

  android = {
    enable = true;
    # Optional: Customize versions
    platforms.version = [ "33" "34" "35" "36" ];
    # buildTools.version = [ "34.0.0" ];

    # Enable emulator and NDK
    # emulator.enable = true;
    ndk.enable = true;

    flutter.enable = true;
  };

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

    rust = {
      enable = true;
      channel = "stable";
      targets = [
        "aarch64-linux-android"
        "i686-linux-android"
        "x86_64-linux-android"
        "armv7-linux-androideabi"
      ];
    };
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
    check-merge-conflicts.enable = false;
    detect-private-keys.enable = false;
  };
}
