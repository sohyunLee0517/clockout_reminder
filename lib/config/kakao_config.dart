/// 카카오 디벨로퍼스에서 발급받은 **네이티브 앱 키**를 여기에 넣으세요.
///
/// 발급 위치: https://developers.kakao.com → 내 애플리케이션 → 앱 설정 → 앱 키 → 네이티브 앱 키
///
/// ⚠️ 이 값을 바꾸면 아래 두 곳도 같은 키로 맞춰야 합니다:
///   - iOS:     ios/Runner/Info.plist 의 CFBundleURLSchemes  →  kakao{네이티브앱키}
///   - Android: android/app/src/main/AndroidManifest.xml 의 kakao{네이티브앱키}://oauth
const String kakaoNativeAppKey = 'e83d32911eb1aec3b93a0db9d3b8bc1a';

/// 키가 채워졌는지 여부(미설정이면 카카오 기능 비활성).
bool get isKakaoConfigured =>
    kakaoNativeAppKey.isNotEmpty &&
    kakaoNativeAppKey != 'YOUR_KAKAO_NATIVE_APP_KEY';
