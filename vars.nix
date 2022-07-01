{ lib, config, ... }:

with lib;

let
  cfg = config.services.vars;
in {
  options.services.vars = {
    user = mkOption {
      type = types.str;
    };
    smbServer = mkOption {
      type = types.str;
    };
  };
}
