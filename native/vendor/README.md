# vp_core selective vendoring

`vp-protocol/` and `vp-dns/` are copied from mateo-ki/vp_core at
`fa3e7430371930c440ffb1bdccc6869c63554a34` (v1.1.0), except the patches below.
The upstream Cargo package declares MIT. Its repository at this commit does
not contain a full license notice; this provenance must be retained and the
upstream notice clarified before distribution. No FlClash code is included.

Only these two crates are patched. Other core crates remain Git dependencies pinned
to the same commit. The local workspace preserves the upstream dependency
constraints and replaces internal relative paths with pinned Git dependencies.
The host Cargo.lock fixes actual resolved dependency versions.

## P001: HTTP authority parsing

`src/inbound/http_in.rs` used `DstAddr::new("host:port", 80)` for absolute-form
and origin-form HTTP requests. This passed the port as part of the DNS name.
The patch parses the authority with the existing `http` crate, applies port 80
only when omitted, handles bracketed IPv6 and rejects invalid ports/userinfo.
It leaves CONNECT and the upstream relay unchanged.

Regression coverage: two parser tests (`flvp_p001_tests`) and real local HTTP
forwarding to a dynamically assigned, non-80 origin port (`tools/verify_host.py`).
The host capability build ID includes `+P001`.

To compare against upstream: `git diff --no-index
core-example/vp_core/crates/vp-protocol native/vendor/vp-protocol`.

## P002: bounded DoT connection and TLS handshake

`vp-dns/src/lib.rs::query_server_raw` now wraps the entire DoT query in
`with_timeout`, matching DoH's existing total `QUERY_TIMEOUT` (3 seconds).
Previously only reads had a deadline; TCP connect or TLS handshake could block
fallback indefinitely. The resolver, root certificates, DNS answers and filter
behavior are otherwise unchanged. No upstream reference checkout was modified.

Regression coverage: `flvp_p002_tests::dot_handshake_has_total_deadline` uses a
local TCP peer that never sends a TLS response. The real Windows host test
`test/dns_runtime_test.dart` verifies fallback after that deadline, plus UDP/TCP
resolution, node bootstrap, filter behavior, rejected updates and restart.
The host build ID includes `+P001+P002`; capabilities list both patches.

Reproduce: `cargo test --locked --manifest-path native/vendor/vp-dns/Cargo.toml
--lib --target-dir native/core-host/target`.
