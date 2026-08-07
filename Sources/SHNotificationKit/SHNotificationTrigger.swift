import Foundation
import UserNotifications

// MARK: - SHNotificationTrigger

/// 언제 울릴지.
///
/// iOS는 앱당 예약 가능한 로컬 알림이 **64개**로 제한된다. 매일 하나씩 미리 넣는
/// 방식은 두 달이면 상한에 닿으므로, 반복 트리거(`.daily`, `.weekly`)를 쓰고
/// 요청 식별자를 재사용해 덮어쓰는 것이 기본이다.
public enum SHNotificationTrigger: Sendable, Equatable {
    /// 매일 같은 시각
    case daily(hour: Int, minute: Int)
    /// 매주 같은 요일·시각. `weekday`는 1=일요일 (Calendar 규약)
    case weekly(weekday: Int, hour: Int, minute: Int)
    /// 지정한 날짜·시각에 한 번
    case once(Date)
    /// 지금부터 일정 시간 뒤에 한 번
    case after(TimeInterval)
    /// 일정 간격으로 반복. iOS는 60초 미만을 허용하지 않는다.
    case every(TimeInterval)

    /// 반복되는 트리거인지
    public var repeats: Bool {
        switch self {
        case .daily, .weekly, .every: true
        case .once, .after: false
        }
    }
}

extension SHNotificationTrigger {
    /// 대응하는 `UNNotificationTrigger`. 값이 유효하지 않으면 `nil`.
    func makeUNTrigger(calendar: Calendar) -> UNNotificationTrigger? {
        switch self {
        case let .daily(hour, minute):
            guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
            return UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: hour, minute: minute),
                repeats: true
            )

        case let .weekly(weekday, hour, minute):
            guard (1...7).contains(weekday),
                  (0...23).contains(hour),
                  (0...59).contains(minute) else { return nil }
            return UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: hour, minute: minute, weekday: weekday),
                repeats: true
            )

        case let .once(date):
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: date
            )
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        case let .after(interval):
            guard interval > 0 else { return nil }
            return UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)

        case let .every(interval):
            // iOS가 반복 간격 60초 미만을 거부한다.
            guard interval >= 60 else { return nil }
            return UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: true)
        }
    }
}

// MARK: - 편의 생성자

public extension SHNotificationTrigger {
    /// `DateComponents`의 시·분으로 매일 반복.
    ///
    /// 계산 결과(`Date`)에서 시·분만 뽑아 예약할 때 쓴다.
    static func daily(at components: DateComponents) -> SHNotificationTrigger {
        .daily(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }

    /// `Date`의 시·분으로 매일 반복.
    static func daily(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> SHNotificationTrigger {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return .daily(at: components)
    }
}
