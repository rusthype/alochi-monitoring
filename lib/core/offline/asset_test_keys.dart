// lib/core/offline/asset_test_keys.dart
//
// The ONE list of `test_key` values the app's built-in ("assets") runners --
// Unit 1, Combined, Interhouse, Bob 1-4 -- put on their results in offline USB
// / LAN mode. The runners stamp them (offline_asset_results.dart) and the LAN
// hub admits exactly these on top of the pack's own keys (shelf_hub.dart). No
// other place may invent an asset key.
//
// Why a namespace and not the runners' native keys (`unit1_eng`,
// `monitoring_unit1`, `interhouse_g2`, `bob1_4`): `unit1_eng`, `interhouse_g2`
// and `bob1_4` are also published server-side as MonitoringTest rows (the
// runners download them online; load_unified_test.py loads the same files). The
// server refuses an offline result whose test_key / detail.test_key is a key it
// KNOWS but the pack does not contain (`test_not_in_pack`,
// offline_pack.py::_test_key_problems), so a result under a native key would be
// dropped at import. Keys the server has never heard of are accepted and stored
// unverified -- and `asset:` is neither a MonitoringTest key nor one of the
// scoring prefixes (`diag:` / `package:` / `pack:`), so it always is. The
// result can then never be mistaken for, or scored as, the pack's real test.

const String kAssetKeyUnit1 = 'asset:unit1_eng';
const String kAssetKeyCombined = 'asset:monitoring_unit1';
const String kAssetKeyInterhouse = 'asset:interhouse_g2';
const String kAssetKeyBob14 = 'asset:bob1_4';

const Set<String> kAssetTestKeys = {
  kAssetKeyUnit1,
  kAssetKeyCombined,
  kAssetKeyInterhouse,
  kAssetKeyBob14,
};
