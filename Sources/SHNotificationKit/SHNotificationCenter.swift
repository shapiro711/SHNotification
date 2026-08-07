import Foundation
import UserNotifications

// MARK: - SHNotificationCenter

/// 로컬 알림 진입점.
///
/// `UNUserNotificationCenter`를 감싸되, 앱이 매번 손으로 하던 세 가지를 흡수한다.
///
/// 1. **델리게이트 배선** — `UNUserNotificationCenterDelegate`는 클래스여야 하고
///    앱 수명 동안 하나만 살아야 한다. Swift 6에서는 여기에 의존성을 들고 있기가
///    까다로워서(키패스가 액터 경계를 넘는다) 싱글턴 + 클로저 주입으로 우회하게 된다.
///    이 타입은 그 델리게이트를 안에 감추고 ``responses`` 스트림만 노출한다.
/// 2. **64개 예약 상한** — 같은 `id`로 다시 예약하면 덮어쓰므로, 반복 트리거와
///    고정 id를 쓰는 한 상한에 닿지 않는다.
/// 3. **Sendable 경계** — `UNNotificationResponse`는 `Sendable`이 아니다.
///    필요한 값만 담은 ``SHNotificationResponse``가 대신 넘어간다.
///
/// ```swift
/// let notifications = SHNotificationCenter.shared
///
/// guard await notifications.requestAuthorization().canSend else { return }
///
/// await notifications.register(categories: [
///     SHNotificationCategory(id: "REMINDER", actions: [
///         SHNotificationAction(id: "DONE", title: "완료")
///     ])
/// ])
///
/// try await notifications.schedule(
///     id: "daily-reminder",
///     trigger: .daily(hour: 21, minute: 0),
///     content: .init(title: "기록할 시간이에요", categoryID: "REMINDER")
/// )
///
/// for await response in notifications.responses where response.action.customID == "DONE" {
///     await markDone()
/// }
/// ```
public final class SHNotificationCenter: Sendable {

    /// 앱 하나에 알림 센터는 하나뿐이므로 공유 인스턴스를 쓴다.
    public static let shared = SHNotificationCenter()

    private let center: @Sendable () -> UNUserNotificationCenter
    private let calendar: Calendar
    private let delegate: SHNotificationDelegate

    /// 테스트에서 다른 센터를 물릴 수 있게 열어 둔다.
    public init(
        center: @escaping @Sendable () -> UNUserNotificationCenter = { .current() },
        calendar: Calendar = .autoupdatingCurrent,
        foregroundPresentation: SHForegroundPresentation = .standard
    ) {
        self.center = center
        self.calendar = calendar
        self.delegate = SHNotificationDelegate(foregroundPresentation: foregroundPresentation)
    }

    // MARK: - 권한

    /// 현재 권한 상태
    public func authorizationStatus() async -> SHAuthorizationStatus {
        let settings = await center().notificationSettings()
        return SHAuthorizationStatus(settings.authorizationStatus)
    }

    /// 권한을 요청한다.
    ///
    /// 시스템 팝업은 앱 생애에 **한 번만** 뜬다. 그래서 왜 필요한지 먼저 설명하고
    /// 부르는 것이 좋다 — 거부되면 되돌릴 방법이 설정 앱 안내밖에 없다.
    @discardableResult
    public func requestAuthorization(
        options: SHAuthorizationOptions = .standard
    ) async -> SHAuthorizationStatus {
        let granted = (try? await center().requestAuthorization(options: options.unOptions)) ?? false
        // provisional은 granted가 true여도 상태가 .provisional이므로 다시 읽는다.
        return granted ? await authorizationStatus() : .denied
    }

    // MARK: - 예약

    /// 알림을 예약한다. 같은 `id`가 이미 있으면 덮어쓴다.
    ///
    /// - Throws: 트리거 값이 유효하지 않거나 시스템이 거부하면 ``SHNotificationError``
    public func schedule(
        id: String,
        trigger: SHNotificationTrigger,
        content: SHNotificationContent
    ) async throws {
        guard let unTrigger = trigger.makeUNTrigger(calendar: calendar) else {
            throw SHNotificationError.invalidTrigger
        }

        let request = UNNotificationRequest(
            identifier: id,
            content: content.makeUNContent(),
            trigger: unTrigger
        )

        do {
            try await center().add(request)
        } catch {
            throw SHNotificationError.schedulingFailed(underlying: error)
        }
    }

    /// 여러 알림을 한 번에 예약한다. 하나라도 실패하면 던진다.
    public func schedule(_ items: [(id: String, trigger: SHNotificationTrigger, content: SHNotificationContent)]) async throws {
        for item in items {
            try await schedule(id: item.id, trigger: item.trigger, content: item.content)
        }
    }

    // MARK: - 취소

    /// 지정한 식별자의 예약을 취소한다.
    public func cancel(ids: [String]) async {
        center().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// 예약을 전부 취소한다. 이미 전달된 알림은 건드리지 않는다.
    public func cancelAll() async {
        center().removeAllPendingNotificationRequests()
    }

    /// 알림 센터에 쌓인 전달 완료 알림을 지운다.
    public func clearDelivered(ids: [String]? = nil) async {
        if let ids {
            center().removeDeliveredNotifications(withIdentifiers: ids)
        } else {
            center().removeAllDeliveredNotifications()
        }
    }

    // MARK: - 조회

    /// 예약돼 있는 알림 목록.
    ///
    /// 64개 상한에 얼마나 가까운지 확인하거나, 설정 화면에서 "다음 알림"을
    /// 보여줄 때 쓴다.
    public func pending() async -> [SHPendingNotification] {
        let requests = await center().pendingNotificationRequests()
        return requests.map(SHPendingNotification.init(request:))
    }

    // MARK: - 액션

    /// 액션 버튼 묶음을 등록한다. 앱 시작 시 한 번 부르면 된다.
    public func register(categories: [SHNotificationCategory]) async {
        center().setNotificationCategories(Set(categories.map { $0.makeUNCategory() }))
    }

    /// 사용자가 알림에 반응한 것들의 스트림.
    ///
    /// 델리게이트를 직접 붙일 필요가 없다. 이 프로퍼티를 처음 읽는 시점에
    /// 델리게이트가 등록된다.
    ///
    /// 여러 곳에서 구독할 수 있고, 각 구독자는 구독 이후의 반응만 받는다.
    public var responses: AsyncStream<SHNotificationResponse> {
        center().delegate = delegate
        return delegate.makeStream()
    }

    /// 앱이 포그라운드일 때의 표시 정책을 바꾼다.
    public func setForegroundPresentation(_ presentation: SHForegroundPresentation) {
        delegate.setForegroundPresentation(presentation)
    }
}
