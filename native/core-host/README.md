# FLVP native host — milestone 0

Pinned to vp_core `fa3e7430371930c440ffb1bdccc6869c63554a34` through Cargo git dependencies, with selective `vp-protocol` / `vp-dns` patches documented in [../vendor/README.md](../vendor/README.md). The ignored example checkout is not a build dependency. Build with the checked-in Cargo.lock and `--locked`. Current development and validation focus on Windows; Android work is paused.

The Windows executable accepts one UTF-8 JSON request per stdin line and emits one response per stdout line. Logs use stderr. EOF restores owned WinINet settings before shutting down the core. No upstream CLI is spawned, no system routes or DNS settings are changed. Current-user LAN WinINet proxy takeover is explicit and journaled; see [Windows lifecycle](../../docs/bridge-windows.md).

Protocol v1 operations: `capabilities`, `status`, `start`, `apply`, `stop`, `quit`, `enableSystemProxy`, `disableSystemProxy`. Mutations require the last observed `expectedGeneration` and `expectedAppliedRevision`. A start/apply argument contains `config` (JSON text), its lowercase SHA-256 as `configHash`, and a positive `revision`. A response echoes `requestId`, `ok`, and `generation`; errors include the actual status so callers can reconcile. Node selection is compiled into a new snapshot and applied, preserving the configuration hash contract.

The host supports a loopback mixed listener, strict subsets of nine typed node protocols, select/non-lazy url-test/fallback groups and basic rules. Custom ordinary-proxy DNS supports validated UDP/TCP/DoT/DoH upstreams and non-Geo fallback filtering. See [configuration scope](../../docs/windows-configurations.md) and [DNS scope](../../docs/dns-compatibility.md). TUN, external controllers, LAN exposure, provider downloads, Fake-IP and unknown fields remain rejected. Additive capabilities describe these boundaries.

`apply` validates before stopping the active instance, starts a new runtime, and restarts the previous snapshot if activation fails. This is a disruptive restart, not a hot reload. Listener readiness requires this instance's successful bind and a real SOCKS handshake. Status describes a local proxy, not system-wide VPN connectivity.

Run `cargo test --manifest-path native/core-host/Cargo.toml -- --test-threads=1` from the root. Tests bind only loopback sockets and never create TUN devices or invoke route cleanup.
