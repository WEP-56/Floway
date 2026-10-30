# vp_core selective vendoring

`vp-protocol/` is copied verbatim from mateo-ki/vp_core at
`fa3e7430371930c440ffb1bdccc6869c63554a34` (v1.1.0), except the patch below.
The upstream Cargo package declares MIT. Its repository at this commit does
not contain a full license notice; this provenance must be retained and the
upstream notice clarified before distribution. No FlClash code is included.

Only this crate is patched. Other core crates remain Git dependencies pinned
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
