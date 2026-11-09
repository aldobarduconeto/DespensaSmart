import 'dart:convert';
import 'package:crypto/crypto.dart';

class SyncAuth {
  final String code;
  SyncAuth(this.code);
  String get group =>
      sha256.convert(utf8.encode('despensa-v1:$code')).toString();
  String sign(String body) =>
      Hmac(sha256, utf8.encode(code)).convert(utf8.encode(body)).toString();
  bool verify(String body, String? signature) {
    final expected = sign(body);
    if (signature == null || signature.length != expected.length) return false;
    var difference = 0;
    for (var i = 0; i < expected.length; i++) {
      difference |= expected.codeUnitAt(i) ^ signature.codeUnitAt(i);
    }
    return difference == 0;
  }
}
