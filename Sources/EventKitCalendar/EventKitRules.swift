import CalendarDomain
import EventKit
import Foundation

extension EventKitDates {
  static func rule(_ spec: RecurrenceSpec, start: Date, allDay: Bool = false) throws
    -> EKRecurrenceRule
  {
    try spec.validate(start: start)
    if !spec.weekdays.isEmpty {
      var cal = Calendar(identifier: .gregorian)
      cal.timeZone = spec.timezone ?? .current
      guard spec.weekdays.contains(cal.component(.weekday, from: start)) else {
        throw CLIError.invalid(
          "Start date must fall on one of --repeat-days. Provide a matching --start date.")
      }
    }
    let frequency: EKRecurrenceFrequency = [
      "daily": .daily, "weekly": .weekly, "monthly": .monthly, "yearly": .yearly,
    ][spec.frequency]!
    let end: EKRecurrenceEnd?
    if let until = spec.until {
      var last = until
      if allDay && spec.untilIsDate {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let day = floatingDate(until, from: spec.timezone ?? .current)
        last = cal.date(byAdding: .day, value: 1, to: day)!.addingTimeInterval(-1)
      }
      end = EKRecurrenceEnd(end: last)
    } else if let count = spec.count {
      end = EKRecurrenceEnd(occurrenceCount: count)
    } else {
      end = nil
    }
    let days = spec.weekdays.map { EKRecurrenceDayOfWeek(EKWeekday(rawValue: $0)!) }
    return EKRecurrenceRule(
      recurrenceWith: frequency, interval: spec.interval, daysOfTheWeek: days.isEmpty ? nil : days,
      daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil,
      setPositions: nil, end: end)
  }
  static func ruleInfo(_ rule: EKRecurrenceRule) -> RecurrenceInfo {
    let frequency = ["daily", "weekly", "monthly", "yearly"][rule.frequency.rawValue]
    let end = rule.recurrenceEnd
    return RecurrenceInfo(
      frequency: frequency, interval: rule.interval,
      weekdays: rule.daysOfTheWeek?.map { $0.dayOfTheWeek.rawValue } ?? [],
      weekdayOrdinals: rule.daysOfTheWeek?.map(\.weekNumber) ?? [],
      monthDays: rule.daysOfTheMonth?.map(\.intValue) ?? [],
      months: rule.monthsOfTheYear?.map(\.intValue) ?? [],
      yearDays: rule.daysOfTheYear?.map(\.intValue) ?? [],
      yearWeeks: rule.weeksOfTheYear?.map(\.intValue) ?? [],
      setPositions: rule.setPositions?.map(\.intValue) ?? [],
      until: end?.endDate.map {
        EventTime.string($0, allDay: false, zone: TimeZone(secondsFromGMT: 0)!)
      },
      count: (end?.occurrenceCount ?? 0) > 0 ? end?.occurrenceCount : nil)
  }
  static func alarmInfo(_ alarm: EKAlarm) -> AlarmInfo {
    if let date = alarm.absoluteDate {
      return AlarmInfo(
        relativeSeconds: nil,
        absoluteDate: EventTime.string(date, allDay: false, zone: TimeZone(secondsFromGMT: 0)!))
    }
    return AlarmInfo(relativeSeconds: alarm.relativeOffset, absoluteDate: nil)
  }
  static func participant(_ participant: EKParticipant) -> ParticipantInfo {
    let url = participant.url.absoluteString
    let email =
      participant.url.scheme?.lowercased() == "mailto"
      ? String(url.dropFirst(7)).removingPercentEncoding : nil
    return ParticipantInfo(name: participant.name, email: email, url: url)
  }
}
