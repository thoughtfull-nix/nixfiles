self: _final: prev: {
  unstable = import self.inputs.unstable {
    inherit (prev.stdenv.hostPlatform) system;
    config = prev.config;
  };
}
