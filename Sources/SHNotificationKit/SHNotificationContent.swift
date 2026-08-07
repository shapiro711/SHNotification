import Foundation
import UserNotifications

// MARK: - SHNotificationContent

/// 알림 하나의 내용.
///
/// 이 모듈은 "무엇을 알릴지"를 전혀 모른다. 문구도 카테고리도 전부 호출부가 정한다.
public struct SHNotificationContent: Sendable, Equatable {
    public var title: String
    public var body: String
    public var subtitle: String?
    /// 액션 버튼을 붙이려면 `register(categories:)`로 등록한 식별자를 준다.
    public var categoryID: String?
    /// 알림을 열었을 때 앱으로 넘길 값. `Codable`이 아니라 문자열 맵인 이유는
    /// `UNNotificationContent.userInfo`가 plist 호환 타입만 받기 때문이다.
    public var userInfo: [String: String]
    public var sound: Sound
    /// 앱 아이콘 배지. `nil`이면 건드리지 않는다.
    public var badge: Int?
    /// 알림 그룹 묶음 식별자
    public var threadID: String?

    public enum Sound: Sendable, Equatable {
        case none
        case `default`
        case named(String)
    }

    public init(
        title: String,
        body: String = "",
        subtitle: String? = nil,
        categoryID: String? = nil,
        userInfo: [String: String] = [:],
        sound: Sound = .default,
        badge: Int? = nil,
        threadID: String? = nil
    ) {
        self.title = title
        self.body = body
        self.subtitle = subtitle
        self.categoryID = categoryID
        self.userInfo = userInfo
        self.sound = sound
        self.badge = badge
        self.threadID = threadID
    }
}

extension SHNotificationContent {
    func makeUNContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let subtitle { content.subtitle = subtitle }
        if let categoryID { content.categoryIdentifier = categoryID }
        if let threadID { content.threadIdentifier = threadID }
        if let badge { content.badge = NSNumber(value: badge) }
        content.userInfo = userInfo

        switch sound {
        case .none: content.sound = nil
        case .default: content.sound = .default
        case .named(let name):
            content.sound = UNNotificationSound(named: UNNotificationSoundName(name))
        }
        return content
    }
}

// MARK: - SHNotificationCategory

/// 알림에 붙는 액션 버튼 묶음.
///
/// 앱 시작 시 한 번 등록해 두면, 해당 `categoryID`를 쓴 알림에 버튼이 달린다.
public struct SHNotificationCategory: Sendable, Equatable {
    public let id: String
    public let actions: [SHNotificationAction]

    public init(id: String, actions: [SHNotificationAction]) {
        self.id = id
        self.actions = actions
    }
}

/// 알림 액션 버튼 하나.
public struct SHNotificationAction: Sendable, Equatable {
    public let id: String
    public let title: String
    /// 눌렀을 때 앱을 앞으로 가져올지
    public let opensApp: Bool
    /// 파괴적 동작으로 표시할지 (빨간 글자)
    public let isDestructive: Bool
    /// 잠금 상태에서도 눌리게 할지
    public let requiresAuthentication: Bool

    public init(
        id: String,
        title: String,
        opensApp: Bool = false,
        isDestructive: Bool = false,
        requiresAuthentication: Bool = false
    ) {
        self.id = id
        self.title = title
        self.opensApp = opensApp
        self.isDestructive = isDestructive
        self.requiresAuthentication = requiresAuthentication
    }
}

extension SHNotificationAction {
    func makeUNAction() -> UNNotificationAction {
        var options: UNNotificationActionOptions = []
        if opensApp { options.insert(.foreground) }
        if isDestructive { options.insert(.destructive) }
        if requiresAuthentication { options.insert(.authenticationRequired) }

        return UNNotificationAction(identifier: id, title: title, options: options)
    }
}

extension SHNotificationCategory {
    func makeUNCategory() -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: id,
            actions: actions.map { $0.makeUNAction() },
            intentIdentifiers: []
        )
    }
}
