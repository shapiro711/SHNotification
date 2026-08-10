# SHNotification

로컬 알림을 **Swift 6 동시성 위에서 안전하게** 쓰기 위한 얇은 레이어입니다.

- iOS 26+, Swift 6 언어 모드 (경고 0)
- 델리게이트를 감추고 `AsyncStream`으로 반응을 준다
- 반복 트리거 + 고정 id로 **64개 예약 상한**을 피한다
- 앱에 `import UserNotifications`가 남지 않는다

## 설치

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/shapiro711/SHNotification.git", from: "1.0.0")
]
```

```swift
.product(name: "SHNotificationKit", package: "SHNotification")
```

```swift
import SHNotificationKit
```

---

## 이 모듈이 흡수하는 것

앱이 매번 손으로 하던 세 가지입니다.

### 1. 델리게이트 배선

`UNUserNotificationCenterDelegate`는 클래스여야 하고 앱 수명 동안 하나만 살아야 합니다.
Swift 6에서 여기에 의존성을 들면 두 가지에 걸립니다.

- `@Dependency`를 저장 프로퍼티로 두면 키패스가 액터 경계를 넘어 막힌다
- 콜백이 받는 `UNNotificationResponse`가 `Sendable`이 아니라 밖으로 못 넘긴다

그래서 보통 싱글턴 + 클로저 주입으로 우회하게 되는데, 그 배선을 모듈이 한 번만 하고
밖으로는 스트림만 줍니다.

```swift
for await response in SHNotificationCenter.shared.responses {
    if response.action.customID == "DONE" { await markDone() }
}
```

### 2. 64개 예약 상한

iOS는 앱당 로컬 알림을 64개까지만 예약합니다. 매일 하나씩 미리 넣으면 두 달이면
막힙니다. **반복 트리거 + 고정 id**를 쓰면 같은 요청을 덮어쓰므로 상한에 닿지 않습니다.

```swift
try await notifications.schedule(
    id: "bedtime",                       // 같은 id면 덮어쓴다
    trigger: .daily(hour: 23, minute: 6), // 반복
    content: .init(title: "누울 시간이에요")
)
```

### 3. Sendable 경계

`UNNotificationResponse`, `UNUserNotificationCenter`는 `Sendable`이 아닙니다.
필요한 값만 담은 `SHNotificationResponse`가 대신 넘어갑니다.

---

## 구성요소

| 타입 | 역할 |
|---|---|
| `SHNotificationCenter` | 진입점. `.shared` |
| `SHNotificationContent` | 제목·본문·카테고리·userInfo·소리·배지 |
| `SHNotificationTrigger` | `.daily` `.weekly` `.once` `.after` `.every` |
| `SHNotificationCategory` / `SHNotificationAction` | 액션 버튼 |
| `SHNotificationResponse` | 사용자 반응 (Sendable) |
| `SHAuthorizationStatus` | `.notDetermined` / `.denied` / `.authorized` |
| `SHPendingNotification` | 예약 현황 |

---

## 사용

### 권한

```swift
let notifications = SHNotificationCenter.shared

let status = await notifications.authorizationStatus()
guard status.canSend else { return }

// 사전 설명 후에 요청 — 시스템 팝업은 앱 생애에 한 번뿐이다
let result = await notifications.requestAuthorization()
```

### 예약

```swift
try await notifications.schedule(
    id: "bedtime",
    trigger: .daily(hour: 23, minute: 6),
    content: SHNotificationContent(
        title: "누울 시간이에요",
        body: "지금 누우면 목표한 만큼 잘 수 있어요",
        categoryID: "BEDTIME"
    )
)

// 계산 결과에서 시·분만 뽑아 매일 반복
try await notifications.schedule(id: "bedtime", trigger: .daily(at: targetDate), content: ...)

.weekly(weekday: 2, hour: 9, minute: 0)   // 1 = 일요일
.once(date)
.after(60 * 30)
.every(60 * 60)                            // 60초 미만은 iOS가 거부 → 미리 막는다
```

### 취소·조회

```swift
await notifications.cancel(ids: ["bedtime"])
await notifications.cancelAll()
await notifications.clearDelivered()

let pending = await notifications.pending()   // 64개 상한 확인, "다음 알림" 표시
```

### 액션 버튼

```swift
await notifications.register(categories: [
    SHNotificationCategory(id: "REMINDER", actions: [
        SHNotificationAction(id: "DONE", title: "완료"),
        SHNotificationAction(id: "SNOOZE", title: "나중에", opensApp: true),
        SHNotificationAction(id: "DELETE", title: "삭제", isDestructive: true)
    ])
])
```

### 포그라운드 표시

```swift
notifications.setForegroundPresentation(.standard)   // 배너 + 소리
notifications.setForegroundPresentation(.none)       // iOS 기본 동작
```

---

## TCA와 함께

모듈을 그대로 쓰지 말고 **이 앱의 알림 정책**을 Client로 감쌉니다.
모듈은 "어떻게 예약하는가", Client는 "언제 무엇을 알리는가"를 맡습니다.

```swift
@DependencyClient
nonisolated struct NotificationClient: Sendable {
    var authorizationStatus: @Sendable () async -> SHAuthorizationStatus = { .notDetermined }
    var reschedule: @Sendable (_ settings: SettingsDTO) async -> Void
}

nonisolated extension NotificationClient: DependencyKey {
    static var liveValue: NotificationClient {
        let notifications = SHNotificationCenter.shared
        return NotificationClient(
            authorizationStatus: { await notifications.authorizationStatus() },
            reschedule: { settings in
                await notifications.cancel(ids: Reminder.allRequests)
                guard settings.reminderEnabled else { return }
                try? await notifications.schedule(
                    id: Reminder.daily,
                    trigger: .daily(at: settings.reminderAt),
                    content: .init(title: "기록할 시간이에요", categoryID: Reminder.category)
                )
            }
        )
    }
}
```

> `extension DependencyValues`와 `DependencyKey` 준수는 `nonisolated`로 표시하세요.
> `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`로 빌드하면 키패스가 `Sendable`이 아니게 됩니다.

---

## 알아둘 제약

**기상 알림 같은 걸 "알람"이라고 부르지 마세요.** iOS 서드파티 앱은 무음·집중 모드를
뚫는 알람을 만들 수 없습니다(Critical Alerts는 Apple 별도 승인이 필요합니다).
앱 문구와 온보딩에서 이를 명시해 오해를 막으세요.

---

## 흔한 실수

| 증상 | 원인 |
|---|---|
| 알림이 안 옴 | 권한 `.denied` / `.every`에 60초 미만 / 예약 64개 초과 |
| 액션 버튼이 안 보임 | `register(categories:)` 누락 또는 `categoryID` 불일치 |
| 반응이 안 잡힘 | `responses`를 구독하지 않음 (구독 시점에 델리게이트가 붙는다) |
| 앱 떠 있을 때 배너 없음 | iOS 기본 동작. `setForegroundPresentation(.standard)` 필요 |
