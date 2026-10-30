## FLVPcore
FLVPcore is an early-development proxy client built on [vp_core](https://github.com/mateo-ki/vp_core), Flutter, and Dart. Development currently targets Windows and Android; other platforms follow after both are stable. The first runnable milestone is a loopback HTTP/SOCKS5 proxy, not a production VPN client.

## Features & Highlights

- Shared strict configuration compiler, UUID node/rule references and immutable runtime snapshots.
- Real native lifecycle, listener readiness checks and restart with rollback.
- Windows JSONL process host; Android JNI host owned by a foreground service.
- User-designed Flutter interface connected to real proxy power, node selection, modes, mixed-port settings and traffic. Local node/rule editors and profile import/export are retained in the older shell and await integration with the new pages.
- No system proxy, TUN/VPN or subscription integration in this milestone.

## Developer

See the [architecture and core integration documents](docs/README.md) for the pinned core research, shared configuration and rule contracts, and Windows/Android communication and lifecycle plans.

See [M0.1 implementation, build instructions and validation](docs/m0-implementation.md) for what actually works today.

See [current Flutter runtime integration and limitations](docs/flutter-client.md) for the production design replica and its backend wiring.

The Flutter project lives directly in this directory: `pubspec.yaml`, `lib/`, `windows/`, and `android/`. The native host, documentation, and build scripts remain in `native/`, `docs/`, and `tools/`.

Build from the repository root:

```powershell
./tools/build_windows.ps1
./tools/build_android.ps1
```

## Disclaimer

## License
MIT

## community
This open-source project is linked to and recognized by the [Linuxdo](https://linux.do/) community
