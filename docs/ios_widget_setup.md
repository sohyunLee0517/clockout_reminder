# iOS 홈 위젯 설정 가이드 (출근/퇴근 버튼)

Android 위젯은 이미 동작합니다. iOS는 위젯 익스텐션 타겟을 Xcode에서 한 번 만들어야 합니다.
아래 순서대로 진행하세요. (예상 5~10분)

> 사전 정보
> - App Group ID: `group.com.isohyeon.clockoutReminder` (Flutter 코드의 `appGroupId` 와 동일)
> - 위젯 코드: 이미 작성됨 → `ios/ClockoutWidget/ClockoutWidget.swift`

## 1. 위젯 익스텐션 타겟 추가
1. Xcode에서 `ios/Runner.xcworkspace` 열기
2. 메뉴 **File → New → Target…**
3. **Widget Extension** 선택 → Next
4. **Product Name: `ClockoutWidget`** 입력
   - **Include Live Activity** 체크 해제
   - **Include Configuration App Intent** 체크 해제
5. Finish → "Activate scheme?" 묻면 **Activate**

→ `ClockoutWidget` 그룹과 자동 생성된 `ClockoutWidget.swift` 가 생깁니다.

## 2. 생성된 코드를 우리 코드로 교체
1. Xcode가 자동 생성한 `ClockoutWidget/ClockoutWidget.swift` 내용을 전부 지우고,
   레포의 `ios/ClockoutWidget/ClockoutWidget.swift` 내용으로 덮어쓰기
   (이미 같은 경로에 우리 파일이 있으니, Xcode에서 그 파일이 타겟에 포함됐는지만 확인)
2. 자동 생성된 다른 파일(`ClockoutWidgetBundle.swift` 등)이 있으면 삭제하거나,
   `@main` 이 우리 `ClockoutWidget` 한 곳에만 있도록 정리

## 3. App Group 추가 (Runner + 위젯, 둘 다)
각 타겟마다 반복:
1. 프로젝트 네비게이터 → **Runner** 프로젝트 → **TARGETS → Runner** 선택
2. **Signing & Capabilities** 탭 → **+ Capability** → **App Groups** 추가
3. **+** 눌러 그룹 추가 → `group.com.isohyeon.clockoutReminder` 입력, 체크
4. **TARGETS → ClockoutWidgetExtension** 선택 후 위 2~3을 **동일하게** 반복

## 4. 서명 팀 설정 (위젯 타겟)
- **TARGETS → ClockoutWidgetExtension → Signing & Capabilities**
- **Automatically manage signing** 체크 → Team 을 Runner 와 동일하게 (`GR8KZU8WJP`)

## 5. Podfile 에 위젯 타겟 추가
`ios/Podfile` 의 `target 'Runner' do … end` **안쪽**(RunnerTests 블록 아래)에 추가:

```ruby
  target 'ClockoutWidgetExtension' do
    use_frameworks!
    use_modular_headers!
    inherit! :search_paths
    pod 'home_widget', :path => '.symlinks/plugins/home_widget/ios'
  end
```

그 후 터미널에서:
```bash
cd ~/Developer/clockout_reminder/ios && pod install
```

## 6. 빌드
```bash
cd ~/Developer/clockout_reminder
flutter build ios --release
xcrun devicectl device install app --device 00008150-000249140A05401C build/ios/Release-iphoneos/Runner.app
```

설치 후 홈 화면 빈 곳을 길게 눌러 **+** → "퇴근 알림" 위젯을 추가하면 됩니다.

> 메모: 위젯 버튼(인터랙티브)은 **iOS 17 이상**에서만 동작합니다. (현재 기기 iOS 26 → OK)
> 버튼을 누르면 앱이 꺼져 있어도 백그라운드에서 출퇴근이 기록되고 위젯이 갱신됩니다.
