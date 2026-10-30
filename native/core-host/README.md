# FLVP native host — milestone 0

Pinned to vp_core `fa3e7430371930c440ffb1bdccc6869c63554a34` through Cargo git dependencies, with the selective `vp-protocol` patch documented in [../vendor/README.md](../vendor/README.md). The ignored example checkout is not a build dependency. Build with the checked-in Cargo.lock and `--locked`.

The Windows executable accepts one UTF-8 JSON request per stdin line and emits one response per stdout line. Logs use stderr. EOF shuts down the owned core. Android calls the same Host through JNI on its service executor. No upstream CLI is spawned, no system routes or proxy settings are changed.

Protocol v1 operations: `capabilities`, `status`, `start`, `apply`, `stop`, `quit`. Mutations require the last observed `expectedGeneration` and `expectedAppliedRevision`. A start/apply argument contains `config` (JSON text), its lowercase SHA-256 as `configHash`, and a positive `revision`. A response echoes `requestId`, `ok`, and `generation`; errors include the actual status so callers can reconcile. Node selection is compiled into a new snapshot and applied, preserving the configuration hash contract.

This milestone deliberately supports only unauthenticated SOCKS5/HTTP upstream nodes, a single selector, strict basic rules, and a loopback mixed listener. Configurations requesting TUN, external controllers, LAN exposure, downloads, credentials or unsupported fields are rejected. Capability flags report the same limitations to the app.

`apply` validates before stopping the active instance, starts a new runtime, and restarts the previous snapshot if activation fails. This is a disruptive restart, not a hot reload. Listener readiness requires this instance's successful bind and a real SOCKS handshake. Status describes a local proxy, not system-wide VPN connectivity.

Run `cargo test --manifest-path native/core-host/Cargo.toml -- --test-threads=1` from the root. Tests bind only loopback sockets and never create TUN devices or invoke route cleanup.
