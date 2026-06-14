import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

/// Alochi rasmlar uchun custom cache manager.
/// - 30 kunlik cache (rasmlar o'zgarmaydi)
/// - Maksimum 500 ta rasm
class AlochiImageCacheManager extends CacheManager with ImageCacheManager {
  static const key = 'alochiImageCache';

  static final AlochiImageCacheManager _instance = AlochiImageCacheManager._();

  factory AlochiImageCacheManager() => _instance;

  AlochiImageCacheManager._()
      : super(
          Config(
            key,
            stalePeriod: const Duration(days: 30),
            maxNrOfCacheObjects: 500,
            repo: JsonCacheInfoRepository(databaseName: key),
            fileService: HttpFileService(
              httpClient: _createHttpClient(),
            ),
          ),
        );
}

http.Client _createHttpClient() {
  return http.Client();
}
