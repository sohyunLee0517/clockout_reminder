import 'package:flutter/foundation.dart';
import 'package:kakao_flutter_sdk_talk/kakao_flutter_sdk_talk.dart';

import '../config/kakao_config.dart';

/// 카카오톡 "나에게 보내기"(나와의 채팅) 연동.
///
/// 각 사용자가 본인 카카오 계정으로 로그인·동의해야 동작한다.
class KakaoService {
  static const _talkMessageScope = 'talk_message';

  /// 카카오 계정이 연결(로그인)되어 있는지.
  static Future<bool> isLinked() async {
    if (!isKakaoConfigured) return false;
    try {
      return await AuthApi.instance.hasToken();
    } catch (_) {
      return false;
    }
  }

  /// 카카오 로그인(카톡 앱 우선, 실패 시 카카오계정).
  static Future<bool> login() async {
    if (!isKakaoConfigured) return false;
    try {
      if (await isKakaoTalkInstalled()) {
        try {
          await UserApi.instance.loginWithKakaoTalk();
        } catch (_) {
          await UserApi.instance.loginWithKakaoAccount();
        }
      } else {
        await UserApi.instance.loginWithKakaoAccount();
      }
      // 메시지 전송 동의 미리 확보(이미 동의됐으면 조용히 넘어감).
      await _ensureTalkMessageScope();
      return true;
    } catch (e) {
      debugPrint('카카오 로그인 실패: $e');
      return false;
    }
  }

  static Future<void> logout() async {
    try {
      await UserApi.instance.logout();
    } catch (e) {
      debugPrint('카카오 로그아웃 실패: $e');
    }
  }

  /// 나와의 채팅방으로 텍스트 메시지 전송. 성공 시 true.
  static Future<bool> sendToMe(String text) async {
    if (!await isLinked()) return false;
    try {
      await _send(text);
      return true;
    } catch (_) {
      // 메시지 전송 미동의 → 추가 동의 후 1회 재시도.
      try {
        await UserApi.instance.loginWithNewScopes([_talkMessageScope]);
        await _send(text);
        return true;
      } catch (e) {
        debugPrint('카카오 메시지 전송 실패: $e');
        return false;
      }
    }
  }

  static Future<void> _send(String text) {
    return TalkApi.instance.sendDefaultMemo(
      TextTemplate(text: text, link: Link()),
    );
  }

  static Future<void> _ensureTalkMessageScope() async {
    try {
      await UserApi.instance.loginWithNewScopes([_talkMessageScope]);
    } catch (_) {
      // 이미 동의했거나 사용자가 취소 — 전송 시점에 다시 처리.
    }
  }
}
