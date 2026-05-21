import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Alochi rasmlar uchun custom cache manager.
/// - 30 kunlik cache (rasmlar o'zgarmaydi)
/// - Maksimum 500 ta rasm
/// - Windows SSL muammosini hal qiladi
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
  if (Platform.isWindows) {
    final httpClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    return IOClient(httpClient);
  }
  return http.Client();
}
