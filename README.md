# 퇴근 알림 (clockout_reminder)

위치(Geofencing)와 시간 기반으로 퇴근 체크를 도와주는 Flutter 앱입니다.
회사 반경을 벗어나거나 퇴근 예정 시간이 되면 로컬 알림으로 "퇴근 체크하셨나요?"를 띄우고,
출퇴근 기록을 로컬 DB에 자동 저장합니다.

## 핵심 기능

| 기능 | 설명 | 구현 |
| --- | --- | --- |
| 위치 기반 감지 | 회사 반경 진입 시 "출근하시겠습니까?" 확인 / 이탈 시 퇴근 자동 | `geofence_service` |
| 회사 위치 지정 | 지도에서 탭으로 회사 좌표·반경 지정 | `flutter_map` (OSM) |
| 근무 규칙 | 근무시간 + 점심시간 + 출퇴근 시간단위(올림) | `TimeRules` |
| 퇴근시각 계산 | 올림한 출근시각 + 근무 + 점심 → 정시 1회 푸시 예약 | `flutter_local_notifications` + `timezone` |
| 근태 기록 로그 | 출퇴근 시각·사유·위치를 로컬 DB 저장/조회 | `sqflite` |
| 설정 저장 | 회사 좌표·반경·근무규칙·on/off | `shared_preferences` |

### 출퇴근 시간 단위(올림) 규칙

출근시각을 단위로 **올림**한 뒤 근무시간을 센다.

- 단위 10분: 8:09 출근 → 8:10 기준
- 단위 1시간: 8:30 출근 → 9:00 기준

`퇴근시각 = 올림(출근시각, 단위) + 근무시간 + 점심시간`
예) 9:09 출근 · 단위 10분 · 근무 8h · 점심 1h → 9:10 + 9h = **18:10**

## 화면

- **홈** (`lib/screens/home_screen.dart`): 오늘 출/퇴근 상태, 위치 감지 상태, 수동 퇴근 체크, 오늘 기록
- **설정** (`lib/screens/settings_screen.dart`): 회사 위치(현재 위치로 지정 가능), 반경, 퇴근 시간, 권한 요청
- **기록** (`lib/screens/history_screen.dart`): 날짜별 근태 기록, 근무 시간 계산, 삭제

## 프로젝트 구조

```
lib/
├── main.dart                       # 진입점: 초기화 + 자동 감시 시작
├── models/
│   ├── app_settings.dart           # 설정 모델
│   └── attendance_record.dart      # 근태 기록 모델
├── services/
│   ├── settings_service.dart       # shared_preferences
│   ├── database_service.dart       # sqflite
│   ├── notification_service.dart   # 로컬 알림 (즉시/예약)
│   ├── geofence_manager.dart       # 지오펜스 감지 → 기록/알림 트리거
│   └── permission_service.dart     # 위치/알림 권한
└── screens/                        # UI
```

## 실행 방법

```bash
flutter pub get
flutter run            # 실기기 권장 (지오펜스/백그라운드 위치는 시뮬레이터에서 제한적)
```

> 위치·알림 기능은 **실기기**에서 테스트하세요. 최초 실행 시 설정 화면에서
> 회사 위치를 지정하고 위치/알림 권한(특히 위치 "항상 허용")을 허용해야 백그라운드 감지가 동작합니다.

## 권한

- **Android** (`android/app/src/main/AndroidManifest.xml`): `ACCESS_FINE/COARSE/BACKGROUND_LOCATION`,
  `FOREGROUND_SERVICE(_LOCATION)`, `POST_NOTIFICATIONS`, `WAKE_LOCK`, `SCHEDULE_EXACT_ALARM` 등
- **iOS** (`ios/Runner/Info.plist`): 위치 사용 설명, `UIBackgroundModes(location, fetch)`

## 계획서 대비 변경 사항

- 계획서의 `flutter_geofencing` 패키지는 **유지보수가 중단**되어 최신 Flutter/Android와 호환되지 않습니다.
  활발히 유지되고 포그라운드 서비스 기반 백그라운드 감지를 지원하는 **`geofence_service`** 로 대체했습니다.
  (참고: `geofence_service`도 최근 `geofencing_api`로 이름이 바뀌며 deprecated 표시가 있으나 현재 버전 6.0.0은 정상 동작합니다.
  추후 `geofencing_api`로 마이그레이션을 권장합니다.)
- 예약 알림 정확도를 위해 `timezone`, 한국어 표시를 위해 `intl` / `flutter_localizations`를 추가했습니다.

## 동작 로직 요약

1. 회사 반경 **진입(ENTER)** → "출근하시겠습니까?" 다이얼로그/알림 → **예** 누르면 출근 기록 + 퇴근시각 계산·예약
2. 회사 반경 **이탈(EXIT)** → 출근했고 퇴근 미체크면 **퇴근** 자동 기록
3. 출근 확정 시 계산된 **퇴근시각에 OS 예약 알림(1회)** 등록 → 정시 푸시 (서버 배치 불필요)
4. 홈 화면의 **출근하기 / 퇴근하기** 버튼으로 수동 처리도 가능

### 퇴근 푸시 배치 방식

출근시각이 매일 달라지므로 "고정 시간 반복" 대신, **출근 확정 시점에 그날 퇴근시각으로 `zonedSchedule`(1회)** 을 건다.
OS의 AlarmManager(Android)/UNUserNotificationCenter(iOS)가 앱이 꺼져 있어도 정시에 알림을 띄우므로 별도 서버나 백그라운드 배치가 필요 없다.
