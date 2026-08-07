import Testing
import Foundation
import UserNotifications
@testable import SHNotificationKit

// MARK: - 트리거

@Suite("SHNotificationTrigger")
struct TriggerTests {

    private let calendar = Calendar(identifier: .gregorian)

    @Test("매일 반복은 시·분만 맞추고 repeats가 켜진다")
    func dailyRepeats() throws {
        let trigger = SHNotificationTrigger.daily(hour: 23, minute: 6)
        let un = try #require(trigger.makeUNTrigger(calendar: calendar) as? UNCalendarNotificationTrigger)

        #expect(un.repeats)
        #expect(un.dateComponents.hour == 23)
        #expect(un.dateComponents.minute == 6)
        // 날짜를 지정하지 않아야 매일 반복된다
        #expect(un.dateComponents.day == nil)
        #expect(trigger.repeats)
    }

    @Test("Date에서 시·분만 뽑아 매일 반복을 만든다")
    func dailyFromDate() throws {
        let date = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 6, hour: 21, minute: 36
        ))!
        let trigger = SHNotificationTrigger.daily(at: date, calendar: calendar)
        #expect(trigger == .daily(hour: 21, minute: 36))
    }

    @Test("주간 반복은 요일을 포함한다")
    func weeklyIncludesWeekday() throws {
        let trigger = SHNotificationTrigger.weekly(weekday: 2, hour: 9, minute: 0)
        let un = try #require(trigger.makeUNTrigger(calendar: calendar) as? UNCalendarNotificationTrigger)

        #expect(un.repeats)
        #expect(un.dateComponents.weekday == 2)
    }

    @Test("단발 예약은 repeats가 꺼진다")
    func onceDoesNotRepeat() throws {
        let date = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 6, hour: 7, minute: 0
        ))!
        let trigger = SHNotificationTrigger.once(date)
        let un = try #require(trigger.makeUNTrigger(calendar: calendar) as? UNCalendarNotificationTrigger)

        #expect(un.repeats == false)
        #expect(trigger.repeats == false)
    }

    @Test("잘못된 시·분은 트리거를 만들지 않는다")
    func rejectsInvalidTime() {
        #expect(SHNotificationTrigger.daily(hour: 24, minute: 0).makeUNTrigger(calendar: calendar) == nil)
        #expect(SHNotificationTrigger.daily(hour: 0, minute: 60).makeUNTrigger(calendar: calendar) == nil)
        #expect(SHNotificationTrigger.weekly(weekday: 8, hour: 9, minute: 0).makeUNTrigger(calendar: calendar) == nil)
    }

    @Test("iOS가 거부하는 60초 미만 반복을 미리 막는다")
    func rejectsTooShortInterval() {
        #expect(SHNotificationTrigger.every(30).makeUNTrigger(calendar: calendar) == nil)
        #expect(SHNotificationTrigger.every(60).makeUNTrigger(calendar: calendar) != nil)
        #expect(SHNotificationTrigger.after(0).makeUNTrigger(calendar: calendar) == nil)
    }
}

// MARK: - 내용

@Suite("SHNotificationContent")
struct ContentTests {

    @Test("UNContent로 값이 그대로 옮겨간다")
    func mapsToUNContent() {
        let content = SHNotificationContent(
            title: "누울 시간이에요",
            body: "지금 누우면 목표한 만큼 잘 수 있어요",
            subtitle: "오늘밤",
            categoryID: "BEDTIME",
            userInfo: ["kind": "bedtime"],
            badge: 1,
            threadID: "sleep"
        )
        let un = content.makeUNContent()

        #expect(un.title == "누울 시간이에요")
        #expect(un.body == "지금 누우면 목표한 만큼 잘 수 있어요")
        #expect(un.subtitle == "오늘밤")
        #expect(un.categoryIdentifier == "BEDTIME")
        #expect(un.threadIdentifier == "sleep")
        #expect(un.badge == 1)
        #expect(un.userInfo["kind"] as? String == "bedtime")
        #expect(un.sound == .default)
    }

    @Test("소리 없음을 지정할 수 있다")
    func silentSound() {
        let un = SHNotificationContent(title: "조용히", sound: .none).makeUNContent()
        #expect(un.sound == nil)
    }

    @Test("액션 옵션이 매핑된다")
    func actionOptions() {
        let action = SHNotificationAction(
            id: "DELETE", title: "삭제", opensApp: true, isDestructive: true
        )
        let un = action.makeUNAction()

        #expect(un.identifier == "DELETE")
        #expect(un.title == "삭제")
        #expect(un.options.contains(.foreground))
        #expect(un.options.contains(.destructive))
    }

    @Test("카테고리에 액션이 붙는다")
    func categoryCarriesActions() {
        let category = SHNotificationCategory(id: "REMINDER", actions: [
            SHNotificationAction(id: "DONE", title: "완료"),
            SHNotificationAction(id: "SNOOZE", title: "나중에")
        ])
        let un = category.makeUNCategory()

        #expect(un.identifier == "REMINDER")
        #expect(un.actions.map(\.identifier) == ["DONE", "SNOOZE"])
    }
}

// MARK: - 권한

@Suite("SHAuthorizationStatus")
struct AuthorizationTests {

    @Test("세 갈래로만 접는다")
    func collapsesToThreeCases() {
        #expect(SHAuthorizationStatus(.notDetermined) == .notDetermined)
        #expect(SHAuthorizationStatus(.denied) == .denied)
        #expect(SHAuthorizationStatus(.authorized) == .authorized)
        // provisional·ephemeral도 "보낼 수 있음"으로 본다
        #expect(SHAuthorizationStatus(.provisional) == .authorized)
    }

    @Test("canSend는 authorized일 때만 참")
    func canSend() {
        #expect(SHAuthorizationStatus.authorized.canSend)
        #expect(SHAuthorizationStatus.denied.canSend == false)
        #expect(SHAuthorizationStatus.notDetermined.canSend == false)
    }

    @Test("요청 옵션 매핑")
    func optionMapping() {
        #expect(SHAuthorizationOptions.standard.unOptions.contains(.alert))
        #expect(SHAuthorizationOptions.standard.unOptions.contains(.sound))
        #expect(SHAuthorizationOptions.standard.unOptions.contains(.badge))
        #expect(SHAuthorizationOptions.standard.unOptions.contains(.provisional) == false)
        #expect(SHAuthorizationOptions([.provisional]).unOptions.contains(.provisional))
    }
}

// MARK: - 반응

@Suite("SHNotificationResponse")
struct ResponseTests {

    @Test("액션 식별자에서 customID를 꺼낸다")
    func customID() {
        #expect(SHNotificationResponse.Action.custom(id: "DONE").customID == "DONE")
        #expect(SHNotificationResponse.Action.opened.customID == nil)
        #expect(SHNotificationResponse.Action.dismissed.customID == nil)
    }

    @Test("Sendable 값이라 액터 경계를 넘길 수 있다")
    func isSendable() async {
        let response = SHNotificationResponse(
            id: "bedtime",
            action: .custom(id: "SLEEP_NOW"),
            categoryID: "BEDTIME",
            userInfo: ["kind": "bedtime"]
        )
        // 다른 격리로 넘겨도 컴파일된다는 것 자체가 검증이다
        let echoed = await Task.detached { response }.value
        #expect(echoed == response)
    }
}

// MARK: - 포그라운드 표시

@Suite("SHForegroundPresentation")
struct ForegroundPresentationTests {

    @Test("표준은 배너 + 소리")
    func standard() {
        let options = SHForegroundPresentation.standard.unOptions
        #expect(options.contains(.banner))
        #expect(options.contains(.sound))
        #expect(options.contains(.badge) == false)
    }

    @Test("none은 아무것도 보여주지 않는다")
    func none() {
        #expect(SHForegroundPresentation.none.unOptions.isEmpty)
    }
}

// MARK: - 반응 스트림

@Suite("반응 스트림")
struct ResponseStreamTests {

    @Test("여러 구독자가 같은 반응을 받는다")
    func broadcastsToAllSubscribers() async throws {
        let delegate = SHNotificationDelegate(foregroundPresentation: .standard)

        var first = delegate.makeStream().makeAsyncIterator()
        var second = delegate.makeStream().makeAsyncIterator()

        let response = SHNotificationResponse(id: "a", action: .custom(id: "DONE"))
        delegate.testOnly_broadcast(response)

        #expect(await first.next() == response)
        #expect(await second.next() == response)
    }

    @Test("스트림이 끝나면 구독이 정리된다")
    func removesTerminatedSubscribers() async throws {
        let delegate = SHNotificationDelegate(foregroundPresentation: .standard)

        do {
            let stream = delegate.makeStream()
            var iterator = stream.makeAsyncIterator()
            delegate.testOnly_broadcast(SHNotificationResponse(id: "a", action: .opened))
            _ = await iterator.next()
        }
        // 구독이 사라진 뒤에도 방송이 터지지 않는다
        delegate.testOnly_broadcast(SHNotificationResponse(id: "b", action: .opened))
    }

    @Test("포그라운드 표시 정책을 바꿀 수 있다")
    func changesForegroundPresentation() {
        let delegate = SHNotificationDelegate(foregroundPresentation: .none)
        delegate.setForegroundPresentation(.standard)
        #expect(delegate.testOnly_foregroundPresentation == .standard)
    }
}
