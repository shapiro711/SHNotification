import Foundation
import UserNotifications
import Synchronization

// MARK: - SHNotificationDelegate

/// `UNUserNotificationCenterDelegate`를 감추고 반응을 스트림으로 바꾼다.
///
/// 델리게이트는 클래스여야 하고 앱 수명 동안 하나만 살아야 한다. 앱이 직접 들면
/// Swift 6에서 두 가지에 걸린다.
///
/// - `@Dependency`를 저장 프로퍼티로 두면 키패스가 액터 경계를 넘어 막힌다
/// - 콜백에서 받은 `UNNotificationResponse`가 `Sendable`이 아니라 밖으로 못 넘긴다
///
/// 그래서 앱은 보통 싱글턴 + 클로저 주입으로 우회하게 되는데, 그 배선을 여기서
/// 한 번만 하고 밖으로는 `AsyncStream`만 준다.
final class SHNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {

    /// 구독자별 continuation. 여러 화면이 동시에 구독할 수 있다.
    private let continuations = Mutex<[UUID: AsyncStream<SHNotificationResponse>.Continuation]>([:])
    private let foregroundPresentation: Mutex<SHForegroundPresentation>

    init(foregroundPresentation: SHForegroundPresentation) {
        self.foregroundPresentation = Mutex(foregroundPresentation)
        super.init()
    }

    func setForegroundPresentation(_ presentation: SHForegroundPresentation) {
        foregroundPresentation.withLock { $0 = presentation }
    }

    /// 새 구독자를 위한 스트림을 만든다.
    func makeStream() -> AsyncStream<SHNotificationResponse> {
        AsyncStream(bufferingPolicy: .bufferingNewest(32)) { continuation in
            let id = UUID()
            continuations.withLock { $0[id] = continuation }
            // Mutex는 ~Copyable이라 캡처 리스트에 담으면 소비된다. self로 접근한다.
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id)
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.withLock { _ = $0.removeValue(forKey: id) }
    }

    private func broadcast(_ response: SHNotificationResponse) {
        let targets = continuations.withLock { Array($0.values) }
        for continuation in targets {
            continuation.yield(response)
        }
    }

    // MARK: - 테스트 지원

    /// 델리게이트 콜백 없이 방송을 확인하기 위한 통로.
    func testOnly_broadcast(_ response: SHNotificationResponse) {
        broadcast(response)
    }

    var testOnly_foregroundPresentation: SHForegroundPresentation {
        foregroundPresentation.withLock { $0 }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// 앱이 떠 있을 때도 보여줄지.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        foregroundPresentation.withLock { $0 }.unOptions
    }

    /// 사용자가 알림을 탭하거나 액션 버튼을 눌렀을 때.
    ///
    /// `UNNotificationResponse`는 여기서 값으로 바꾸고 밖으로는 내보내지 않는다.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        broadcast(SHNotificationResponse(response: response))
    }
}
