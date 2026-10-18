# offline_keys

PUBLIC halves of the prod backend `OFFLINE_PACK_SIGNING_KEY` (signing_public.pem)
and `OFFLINE_RESULTS_RSA_KEY` (results_public.pem). Baked into release builds via
`--dart-define=OFFLINE_*_PUBKEY_B64` (see build-windows.yml / build-macos.yml).

Private halves live only in the prod backend `.env`. Regenerate the public keys
with `python manage.py offline_public_keys`. Replacing keys invalidates all
previously issued packs.
