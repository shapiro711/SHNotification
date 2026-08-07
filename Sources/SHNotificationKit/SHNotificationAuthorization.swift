import Foundation
import UserNotifications

// MARK: - SHAuthorizationStatus

/// 알림 권한 상태.
///
/// `UNAuthorizationStatus`를 그대로 노출하지 않는 이유는, 앱이 실제로 분기하는
/// 경우가 세 갈래뿐이기 때문이다 — 아직 안 물어봄 / 거부됨 / 보낼 수 있음.
public enum SHAuthorizationStatus: String, Sendable, Equatable {
    /// 아직 물어보지 않았다. 사전 설명 후 요청하기 좋은 시점
    case notDetermined
    /// 거부됐다. 설정 앱으로 보내는 것 말고는 방법이 없다
    case denied
    /// 보낼 수 있다 (임시 허용·프로비저널 포함)
    case authorized

    public init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        default: self = .authorized
        }
    }

    /// 알림을 보낼 수 있는 상태인지
    public var canSend: Bool { self == .authorized }
}

// MARK: - SHAuthorizationOptions

/// 무엇을 요청할지.
public struct SHAuthorizationOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let alert = SHAuthorizationOptions(rawValue: 1 << 0)
    public static let sound = SHAuthorizationOptions(rawValue: 1 << 1)
    public static let badge = SHAuthorizationOptions(rawValue: 1 << 2)
    /// 사용자에게 묻지 않고 조용히 보내다가, 사용자가 원하면 승격시키는 방식
    public static let provisional = SHAuthorizationOptions(rawValue: 1 << 3)

    public static let standard: SHAuthorizationOptions = [.alert, .sound, .badge]

    var unOptions: UNAuthorizationOptions {
        var options: UNAuthorizationOptions = []
        if contains(.alert) { options.insert(.alert) }
        if contains(.sound) { options.insert(.sound) }
        if contains(.badge) { options.insert(.badge) }
        if contains(.provisional) { options.insert(.provisional) }
        return options
    }
}

// MARK: - SHNotificationError

public enum SHNotificationError: LocalizedError, Sendable {
    /// 트리거 값이 유효하지 않다 (시·분 범위, 60초 미만 반복 등)
    case invalidTrigger
    /// 시스템이 예약을 거부했다
    case schedulingFailed(underlying: any Error)

    public var errorDescription: String? {
        switch self {
        case .invalidTrigger:
            return "알림 시각이 올바르지 않습니다"
        case .schedulingFailed(let error):
            return "알림 예약에 실패했습니다: \(error.localizedDescription)"
        }
    }

    public var failureReason: String? {
        switch self {
        case .invalidTrigger:
            return "시·분 범위를 벗어났거나, 반복 간격이 60초 미만입니다"
        case .schedulingFailed:
            return "권한이 없거나 예약 한도(64개)를 넘었을 수 있습니다"
        }
    }
}

// MARK: - SHPendingNotification

/// 예약돼 있는 알림.
public struct SHPendingNotification: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let body: String
    /// 다음에 울릴 시각. 계산할 수 없으면 `nil`
    public let nextTriggerDate: Date?
    public let repeats: Bool

    public init(
        id: String,
        title: String,
        body: String,
        nextTriggerDate: Date?,
        repeats: Bool
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.nextTriggerDate = nextTriggerDate
        self.repeats = repeats
    }

    init(request: UNNotificationRequest) {
        self.id = request.identifier
        self.title = request.content.title
        self.body = request.content.body

        switch request.trigger {
        case let calendar as UNCalendarNotificationTrigger:
            self.nextTriggerDate = calendar.nextTriggerDate()
            self.repeats = calendar.repeats
        case let interval as UNTimeIntervalNotificationTrigger:
            self.nextTriggerDate = interval.nextTriggerDate()
            self.repeats = interval.repeats
        default:
            self.nextTriggerDate = nil
            self.repeats = false
        }
    }
}
