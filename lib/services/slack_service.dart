import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 슬랙 Incoming Webhook 으로 메시지를 보낸다.
class SlackService {
  /// 웹훅 URL 형식이 그럴듯한지 간단 검증.
  static bool isValidWebhook(String url) {
    final u = url.trim();
    return u.startsWith('https://hooks.slack.com/');
  }

  /// 메시지 전송. 성공 시 true.
  static Future<bool> send(String webhookUrl, String text) async {
    final url = webhookUrl.trim();
    if (!isValidWebhook(url)) return false;
    try {
      final resp = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': text}),
          )
          .timeout(const Duration(seconds: 8));
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('슬랙 전송 실패: $e');
      return false;
    }
  }
}
