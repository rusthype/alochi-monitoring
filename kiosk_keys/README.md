# kiosk_keys

`command_public.pem` is the Ed25519 PUBLIC key the kiosk app uses to verify
signed admin commands (remote `force_update`, see
`lib/core/diagnostics/kiosk_command_auth.dart`).

- Public key only. Never commit a private key here.
- The private key lives only in the backend environment
  (`KIOSK_COMMAND_SIGNING_KEY`).
- The release workflows (`build-windows.yml`, `build-macos.yml`,
  `offline-windows-verify.yml`) base64 this file into
  `--dart-define=KIOSK_COMMAND_PUBKEY_B64=...` and fail the build if it is
  missing, is not an Ed25519 public key, or contains `PRIVATE`.
- Rotation = replace this file together with the backend signing key and ship
  a new build; installed apps keep the key they were built with.
