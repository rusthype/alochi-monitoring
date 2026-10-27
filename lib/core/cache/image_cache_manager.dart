import 'dart:async';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

/// Alochi rasmlar uchun custom cache manager.
/// - 30 kunlik cache (rasmlar o'zgarmaydi)
/// - Maksimum 2000 ta rasm (yuklab olingan testlar rasmlari semestr davomida
///   chiqib ketmasligi uchun; avval 500 edi)
class AlochiImageCacheManager extends CacheManager with ImageCacheManager {
  static const key = 'alochiImageCache';

  static final AlochiImageCacheManager _instance = AlochiImageCacheManager._();

  factory AlochiImageCacheManager() => _instance;

  AlochiImageCacheManager._()
      : super(
          Config(
            key,
            stalePeriod: const Duration(days: 30),
            maxNrOfCacheObjects: 2000,
            repo: JsonCacheInfoRepository(databaseName: key),
            fileService: HttpFileService(
              httpClient: _createHttpClient(),
            ),
          ),
        );
}

/// Windows'da SSL handshake yoki tarmoq uzilishida so'rov abadiy osilib
/// qolishining oldini oladi (diagnostic-image-eternal-spinner) — shundan
/// keyin CachedNetworkImage'ning mavjud errorWidget'i ishga tushadi.
class _TimeoutHttpClient extends http.BaseClient {
  _TimeoutHttpClient(this._inner, this._timeout);
  final http.Client _inner;
  final Duration _timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner.send(request).timeout(_timeout);
  }

  @override
  void close() => _inner.close();
}

http.Client _createHttpClient() {
  return _TimeoutHttpClient(http.Client(), const Duration(seconds: 5));
}
