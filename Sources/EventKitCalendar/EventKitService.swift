import AppKit
import CalendarDomain
import EventKit
import Foundation

public final class EventKitService: CalendarService {
  let store = EKEventStore()
  public init() {}
  public func authorization() -> AuthInfo {
    let state = EKEventStore.authorizationStatus(for: .event)
    let name: String
    switch state {
    case .notDetermined: name = "notDetermined"
    case .restricted: name = "restricted"
    case .denied: name = "denied"
    case .fullAccess: name = "fullAccess"
    case .writeOnly: name = "writeOnly"
    @unknown default: name = "unknown"
    }
    return AuthInfo(status: name, fullAccess: state == .fullAccess)
  }
  public func requestAccess() throws -> AuthInfo {
    if authorization().fullAccess { return authorization() }
    let state = authorization().status
    if state == "denied" || state == "restricted" {
      throw CLIError(
        "PERMISSION_DENIED",
        "Calendar access is \(state). Enable icli or its launching app in System Settings > Privacy & Security > Calendars.",
        exitCode: 3)
    }
    let lock = NSLock()
    var complete = false
    var failure: Error?
    store.requestFullAccessToEvents { _, error in
      lock.lock()
      failure = error
      complete = true
      lock.unlock()
    }
    let deadline = Date().addingTimeInterval(120)
    while true {
      lock.lock()
      let finished = complete
      let error = failure
      lock.unlock()
      if finished {
        if let error { throw CLIError("PERMISSION_ERROR", error.localizedDescription, exitCode: 3) }
        break
      }
      guard Date() < deadline else {
        throw CLIError(
          "PERMISSION_TIMEOUT", "Authorization timed out. Respond to the macOS prompt, then retry.",
          exitCode: 3)
      }
      _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    try requireAccess()
    store.reset()
    return authorization()
  }
  func requireAccess() throws {
    guard authorization().fullAccess else {
      throw CLIError(
        "PERMISSION_REQUIRED",
        "Full calendar access required. Run 'icli cal auth request'; if denied, enable access in System Settings > Privacy & Security > Calendars.",
        exitCode: 3)
    }
  }
  public func calendars() throws -> [CalendarInfo] {
    try requireAccess()
    let defaultID = store.defaultCalendarForNewEvents?.calendarIdentifier
    return store.calendars(for: .event).map { calendarDTO($0, defaultID: defaultID) }
      .sorted { ($0.title, $0.id) < ($1.title, $1.id) }
  }
  func calendarDTO(_ calendar: EKCalendar, defaultID: String? = nil) -> CalendarInfo {
    var color: String?
    if let cgColor = calendar.cgColor, let rgb = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) {
      color = String(
        format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
        Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }
    return CalendarInfo(
      id: calendar.calendarIdentifier, title: calendar.title, source: calendar.source.title,
      writable: calendar.allowsContentModifications,
      isDefault: calendar.calendarIdentifier
        == (defaultID ?? store.defaultCalendarForNewEvents?.calendarIdentifier),
      sourceID: calendar.source.sourceIdentifier, color: color,
      manageable: calendar.allowsContentModifications && !calendar.isImmutable)
  }
  func calendar(_ selector: String?, writable: Bool = false) throws -> EKCalendar {
    let info = try CalendarSelection.resolve(selector, in: calendars(), requireWritable: writable)
    guard let calendar = store.calendar(withIdentifier: info.id) else {
      throw CLIError("NOT_FOUND", "Calendar no longer exists.", exitCode: 4)
    }
    return calendar
  }
  private func recurring(_ event: EKEvent) -> Bool { event.hasRecurrenceRules || event.isDetached }
  private func identifier(_ event: EKEvent) -> String {
    let id = event.eventIdentifier ?? ""
    guard !id.isEmpty else { return "" }
    guard recurring(event) else { return id }
    return OccurrenceID(
      identifier: id, start: event.startDate, calendar: event.calendar.calendarIdentifier
    ).encoded()
  }
  private func dto(_ event: EKEvent) -> EventInfo {
    let zone = event.timeZone ?? .current
    return EventInfo(
      id: identifier(event), calendarID: event.calendar.calendarIdentifier,
      title: event.title ?? "",
      start: EventTime.string(event.startDate, allDay: event.isAllDay, zone: zone),
      end: EventTime.string(EventKitDates.exclusiveEnd(event), allDay: event.isAllDay, zone: zone),
      allDay: event.isAllDay,
      timezone: event.isAllDay ? nil : zone.identifier, location: event.location,
      notes: event.notes,
      recurring: recurring(event),
      writable: event.calendar.allowsContentModifications && !event.hasAttendees,
      alarms: (event.alarms ?? []).map(EventKitDates.alarmInfo),
      recurrenceRules: (event.recurrenceRules ?? []).map(EventKitDates.ruleInfo),
      attendees: (event.attendees ?? []).map(EventKitDates.participant),
      organizer: event.organizer.map(EventKitDates.participant))
  }
  public func events(from: Date, to: Date, calendar selector: String?) throws -> [EventInfo] {
    try events(from: from, to: to, calendars: selector.map { [$0] } ?? [])
  }
  public func events(from: Date, to: Date, calendars selectors: [String]) throws -> [EventInfo] {
    try requireAccess()
    try EventTime.validate(start: from, end: to)
    guard to.timeIntervalSince(from) <= 366 * 86400 else {
      throw CLIError.invalid("Query range cannot exceed 366 days.")
    }
    var selected: [EKCalendar] = []
    var seen = Set<String>()
    for selector in selectors {
      let value = try calendar(selector)
      if seen.insert(value.calendarIdentifier).inserted { selected.append(value) }
    }
    let predicate = store.predicateForEvents(
      withStart: EventKitDates.candidateStart(from), end: to,
      calendars: selected.isEmpty ? nil : selected)
    return store.events(matching: predicate).filter {
      EventKitDates.overlaps($0, from: from, to: to)
    }
    .sorted { ($0.startDate!, identifier($0)) < ($1.startDate!, identifier($1)) }.map(dto)
  }
  private func lookup(_ id: String) throws -> EKEvent {
    try requireAccess()
    if id.hasPrefix(OccurrenceID.prefix) {
      let key = try OccurrenceID.decode(id)
      guard let calendar = store.calendar(withIdentifier: key.calendar) else {
        throw CLIError("NOT_FOUND", "Occurrence calendar no longer exists.", exitCode: 4)
      }
      let start = Date(timeIntervalSince1970: key.start)
      let predicate = store.predicateForEvents(
        withStart: start, end: start.addingTimeInterval(1), calendars: [calendar])
      if let result = store.events(matching: predicate).first(where: {
        $0.eventIdentifier == key.identifier && abs($0.startDate.timeIntervalSince(start)) < 0.001
      }) {
        return result
      }
    } else if let event = store.event(withIdentifier: id) {
      return event
    }
    throw CLIError(
      "NOT_FOUND", "Event not found. Refresh its ID with 'icli cal events list'.", exitCode: 4)
  }
  public func event(id: String) throws -> EventInfo { dto(try lookup(id)) }
  private func requireWritable(_ event: EKEvent) throws {
    guard event.calendar.allowsContentModifications else {
      throw CLIError("READ_ONLY", "Event calendar is read-only.", exitCode: 5)
    }
    guard !event.hasAttendees else {
      throw CLIError(
        "INVITATION_UNSUPPORTED", "Editing or deleting events with attendees is not supported yet.",
        exitCode: 5)
    }
  }
  public func create(_ draft: EventDraft, dryRun: Bool) throws -> MutationResult {
    try requireAccess()
    try EventTime.validate(start: draft.start, end: draft.end)
    guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CLIError.invalid("Title cannot be empty.")
    }
    let event = EKEvent(eventStore: store)
    event.calendar = try calendar(draft.calendar, writable: true)
    event.title = draft.title
    EventKitDates.apply(draft, to: event)
    event.location = draft.location
    event.notes = draft.notes
    if let alerts = draft.alerts { event.alarms = alerts.map { EKAlarm(relativeOffset: $0) } }
    if let recurrence = draft.recurrence {
      event.recurrenceRules = [
        try EventKitDates.rule(recurrence, start: draft.start, allDay: draft.allDay)
      ]
    }
    if !dryRun { try store.save(event, span: .thisEvent, commit: true) }
    return MutationResult(action: "create", dryRun: dryRun, event: dto(event))
  }
  public func update(id: String, patch: EventPatch, scope: EventScope?, dryRun: Bool) throws
    -> MutationResult
  {
    try patch.validate()
    let selected = try lookup(id)
    try requireWritable(selected)
    let resolvedScope = try ScopePolicy.resolve(
      recurring: recurring(selected), scope: scope,
      changingRule: patch.recurrence != nil || patch.clearRecurrence)
    let event = try scopedEvent(selected, scope: resolvedScope)
    try requireWritable(event)
    let before = dto(event)
    let originalTimezone = event.timeZone
    let original = EventDraft(
      calendar: event.calendar.calendarIdentifier, title: event.title ?? "",
      start: event.startDate, end: EventKitDates.exclusiveEnd(event), allDay: event.isAllDay,
      timezone: event.timeZone ?? .current, location: event.location, notes: event.notes)
    let updated = try patch.applying(to: original)
    if let selector = patch.calendar { event.calendar = try calendar(selector, writable: true) }
    if patch.title != nil { event.title = updated.title }
    if patch.start != nil || patch.end != nil || patch.timezone != nil {
      EventKitDates.apply(updated, to: event)
      if !original.allDay && patch.timezone == nil { event.timeZone = originalTimezone }
    }
    if patch.clearLocation || patch.location != nil { event.location = updated.location }
    if patch.clearNotes || patch.notes != nil { event.notes = updated.notes }
    if let alerts = patch.alerts { event.alarms = alerts.map { EKAlarm(relativeOffset: $0) } }
    if patch.clearRecurrence {
      event.recurrenceRules = []
    } else if let recurrence = patch.recurrence {
      event.recurrenceRules = [
        try EventKitDates.rule(recurrence, start: updated.start, allDay: updated.allDay)
      ]
    }
    if !dryRun {
      try store.save(event, span: resolvedScope == .this ? .thisEvent : .futureEvents, commit: true)
    }
    return MutationResult(
      action: "update", dryRun: dryRun, event: dto(event), before: before, scope: resolvedScope)
  }
  private func scopedEvent(_ event: EKEvent, scope: EventScope) throws -> EKEvent {
    guard recurring(event), scope != .this else { return event }
    if scope == .future {
      guard !event.isDetached else {
        throw CLIError(
          "DETACHED_SCOPE",
          "Use an unmodified occurrence for --scope future; detached occurrences support --scope this.",
          exitCode: 5)
      }
      return event
    }
    // EventKit returns the first occurrence, so futureEvents on it targets the series.
    guard let master = store.event(withIdentifier: event.eventIdentifier),
      master.hasRecurrenceRules,
      !master.isDetached, master.calendar.calendarIdentifier == event.calendar.calendarIdentifier,
      master.startDate <= event.startDate
    else {
      throw CLIError(
        "SERIES_NOT_FOUND",
        "Cannot safely locate the series start. Select an unmodified occurrence and retry.",
        exitCode: 5)
    }
    return master
  }
  public func delete(id: String, scope: EventScope?, dryRun: Bool) throws -> MutationResult {
    let selected = try lookup(id)
    try requireWritable(selected)
    let resolvedScope = try ScopePolicy.resolve(recurring: recurring(selected), scope: scope)
    let event = try scopedEvent(selected, scope: resolvedScope)
    try requireWritable(event)
    let before = dto(event)
    if !dryRun {
      try store.remove(
        event, span: resolvedScope == .this ? .thisEvent : .futureEvents, commit: true)
    }
    return MutationResult(
      action: "delete", dryRun: dryRun, event: before, before: before, scope: resolvedScope)
  }
}
