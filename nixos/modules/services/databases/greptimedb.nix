{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    escapeShellArgs
    getExe
    literalExpression
    mkEnableOption
    mkIf
    mkOption
    mkPackageOption
    types
    ;

  cfg = config.services.greptimedb;
  settingsFormat = pkgs.formats.toml { };
  configFile = settingsFormat.generate "greptimedb.toml" cfg.settings;
in
{
  options.services.greptimedb = {
    enable = mkEnableOption "GreptimeDB in standalone mode";

    package = mkPackageOption pkgs "greptimedb" { };

    stateDir = mkOption {
      type = types.str;
      default = "greptimedb";
      description = ''
        Directory below {file}`/var/lib` in which GreptimeDB stores its data.
        It is created automatically using systemd's `StateDirectory` mechanism.
      '';
    };

    settings = mkOption {
      type = types.submodule {
        freeformType = settingsFormat.type;
      };
      default = { };
      example = literalExpression ''
        {
          http.addr = "127.0.0.1:4000";
          grpc.bind_addr = "127.0.0.1:4001";
          mysql = {
            enable = false;
            addr = "127.0.0.1:4002";
          };
          postgres = {
            enable = true;
            addr = "127.0.0.1:4003";
          };
          logging = {
            dir = "";
            append_stdout = true;
          };
        }
      '';
      description = ''
        GreptimeDB standalone configuration written as TOML. See the
        [GreptimeDB configuration documentation](https://docs.greptime.com/user-guide/deployments-administration/configuration/)
        for supported values.
      '';
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "--log-level=debug" ];
      description = "Additional command-line arguments passed to GreptimeDB.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.greptimedb = {
      description = "GreptimeDB standalone database";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = escapeShellArgs (
          [
            (getExe cfg.package)
            "standalone"
            "start"
            "--data-home"
            "/var/lib/${cfg.stateDir}/data"
            "--config-file"
            configFile
          ]
          ++ cfg.extraArgs
        );

        DynamicUser = true;
        StateDirectory = cfg.stateDir;
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/${cfg.stateDir}";
        UMask = "0077";

        Restart = "on-failure";
        RestartSec = "5s";
        LimitNOFILE = 65536;

        LockPersonality = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RemoveIPC = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
      };
    };
  };
}
