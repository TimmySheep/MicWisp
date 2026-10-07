# micyou-cli JSONL bridge patch

This is a GPL-3.0 patch set for the upstream CLI, not a modification of the read-only `upstream-micyou/` checkout. It targets upstream commit `0c69fdd4b0c26553bd4a74aed38a808f0fce621a` (2026-10-08). The new bridge source is original third-party frontend integration code; it does not copy upstream implementation files.

## Apply to a separate writable upstream checkout

Do not apply this patch to the repository's read-only `upstream-micyou/` reference. Make a separate writable checkout at the exact baseline commit, then run the repository-level script:

```sh
sh core/apply-patches.sh /path/to/writable/upstream-micyou-checkout
```

The script refuses a dirty checkout, a different baseline, or an existing `micyou-cli/src/jsonl.rs`. It then adds this bridge module and applies the integration patch.

## Protocol v1

- Ready: `{"v":1,"type":"ready","payload":{"protocolVersion":1,"backendVersion":"...","message":"..."}}`
- Request: `{"v":1,"type":"command","id":"unique-id","name":"...","payload":{...}}`
- Response: `{"v":1,"type":"response","id":"unique-id","ok":true,"payload":{...}}` or an `error` object with `code` and `message`.
- Event: `{"v":1,"type":"event","name":"...","payload":{...}}`
- Maximum input line is 64 KiB. Unknown versions, frame types, and commands are rejected. The bridge does not accept shell commands or open a local network control port.
- Every `ServerEvents` callback has a JSON mapping. Audio metrics are capped at 2 Hz, level at 20 Hz, and spectrum at 10 Hz; only these telemetry events may be dropped if the bounded queue is full. Connection, mute and lifecycle transitions use the retained queue path. The ready frame is written before events collected during server startup.
- Commands: `stop`, `setMuted` (`isMuted`), `setMonitoring` (`enabled`), `getDspSettings`, `applyDspSettings` (full settings object), `setSpectrumStreaming` (`enabled`), `getConnectionSettings`, `applyConnectionSettings` (full settings object; returns `requiresRestart: true`), `listAudioDevices`, `listAdbDevices`, and `getVirtualAudioStatus`.

## GPL notice

The added module is marked as a 2026 modification and licensed under GPL-3.0-or-later. Existing upstream copyright and license headers remain intact. The complete corresponding source is this patch set plus the named upstream source at the pinned commit; downstream releases must make both available under GPL-3.0 and present Appropriate Legal Notices in each native client.
