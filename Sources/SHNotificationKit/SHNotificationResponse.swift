import Foundation
import UserNotifications

// MARK: - SHNotificationResponse

/// 사용자가 알림에 반응한 결과.
///
/// `UNNotificationResponse`는 `Sendable`이 아니라 액터 경계를 넘길 수 없다.
/// 필요한 값만 뽑아 담은 이 구조체가 대신 넘어간다.
public struct SHNotificationResponse: Sendable, Equatable, Identifiable {
    /// 반응한 알림의 요청 식별자 (`schedule`에 넘긴 `id`)
    public let id: String
    /// 눌린 액션. 알림 본문을 탭했으면 `.opened`, 지웠으면 `.dismissed`
    public let action: Action
    public let categoryID: String?
    public let userInfo: [String: String]
    public let receivedAt: Date

    public enum Action: Sendable, Equatable {
        /// 알림 자체를 탭해 앱을 열었다
        case opened
        /// 알림을 지웠다
        case dismissed
        /// 액션 버튼을 눌렀다
        case custom(id: String)

        /// 눌린 액션 버튼의 식별자. 버튼이 아니면 `nil`
        public var customID: String? {
            if case let .custom(id) = self { return id }
            return nil
        }
    }

    public init(
        id: String,
        action: Action,
        categoryID: String? = nil,
        userInfo: [String: String] = [:],
        receivedAt: Date = Date()
    ) {
        self.id = id
        self.action = action
        self.categoryID = categoryID
        self.userInfo = userInfo
        self.receivedAt = receivedAt
    }

    init(response: UNNotificationResponse, now: Date = Date()) {
        let request = response.notification.request
        self.id = request.identifier
        self.categoryID = request.content.categoryIdentifier.isEmpty
            ? nil
            : request.content.categoryIdentifier
        self.userInfo = request.content.userInfo.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }
        self.receivedAt = now

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier: self.action = .opened
        case UNNotificationDismissActionIdentifier: self.action = .dismissed
        default: self.action = .custom(id: response.actionIdentifier)
        }
    }
}

// MARK: - 앱이 떠 있을 때의 표시 정책

/// 앱이 포그라운드일 때 알림을 어떻게 보여줄지.
public struct SHForegroundPresentation: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let banner = SHForegroundPresentation(rawValue: 1 << 0)
    public static let sound = SHForegroundPresentation(rawValue: 1 << 1)
    public static let badge = SHForegroundPresentation(rawValue: 1 << 2)
    public static let list = SHForegroundPresentation(rawValue: 1 << 3)

    /// 아무것도 보여주지 않는다 (iOS 기본 동작)
    public static let none: SHForegroundPresentation = []
    /// 배너 + 소리 — 대부분의 앱이 원하는 값
    public static let standard: SHForegroundPresentation = [.banner, .sound]

    var unOptions: UNNotificationPresentationOptions {
        var options: UNNotificationPresentationOptions = []
        if contains(.banner) { options.insert(.banner) }
        if contains(.sound) { options.insert(.sound) }
        if contains(.badge) { options.insert(.badge) }
        if contains(.list) { options.insert(.list) }
        return options
    }
}
