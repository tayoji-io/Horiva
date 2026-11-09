import AppKit
import SwiftUI
import ClockCore

struct TimeDetailsView: View {
    @ObservedObject var store: SettingsStore
    let meetingMode: Bool
    @State private var selectedDate = Date()
    @State private var followsNow = true
    @State private var copiedZone: String?

    init(store: SettingsStore, meetingMode: Bool = false) {
        self.store = store
        self.meetingMode = meetingMode
        _followsNow = State(initialValue: !meetingMode)
    }

    private func t(_ text: String) -> String { store.settings.language.localized(text) }

    var body: some View {
        TimelineView(store.timelineSchedule) { context in
            let date = followsNow ? context.date : selectedDate
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(t(meetingMode ? "跨时区会议换算器" : "日历与时区")).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(t("运行中")).font(.system(size: 10, weight: .medium)).foregroundStyle(.green)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 5))
                }.padding(.horizontal, 10).padding(.top, 2)
                calendar(at: date)
                if store.settings.zones.count <= 3 {
                    zoneRows(at: date)
                } else {
                    ScrollView { zoneRows(at: date) }.frame(height: 200)
                }
            }.padding(8).frame(width: 420)
        }
        .environment(\.locale, store.settings.language.locale)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func zoneRows(at date: Date) -> some View {
        VStack(spacing: 2) {
            ForEach(Array(store.settings.zones.enumerated()), id: \.element.id) { index, zone in
                zoneRow(zone, index: index, at: date)
            }
        }
    }

    private func calendar(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(t(followsNow ? "日历与时区" : "会议时间")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(t("返回当前时间")) { followsNow = true }.buttonStyle(.borderless).font(.system(size: 11))
            }
            ZonedDatePicker(selection: Binding(
                get: { date },
                set: { selectedDate = $0; followsNow = false }
            ), timeZone: store.settings.timeZone(for: store.settings.zones[0]),
               locale: store.settings.language.locale, graphical: true)
                .fixedSize().frame(maxWidth: .infinity)
            HStack {
                Text(store.settings.zones[0].label).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                ZonedDatePicker(selection: Binding(
                    get: { date },
                    set: { selectedDate = $0; followsNow = false }
                ), timeZone: store.settings.timeZone(for: store.settings.zones[0]),
                   locale: store.settings.language.locale, graphical: false).fixedSize()
            }
            Text(t("以首个时区选择日期与时间，其余时区同步换算。"))
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(10)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    private func zoneRow(_ zone: ClockZone, index: Int, at date: Date) -> some View {
        let comparison = store.settings.comparison(for: zone, at: date)
        let time = store.renderer.string(for: zone, at: date)
        return Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("\(zone.label) \(time) (\(zone.id))", forType: .string)
            copiedZone = zone.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copiedZone == zone.id { copiedZone = nil }
            }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Circle().fill(index == 0 ? Color.green : Color.cyan).frame(width: 7, height: 7)
                    Text(zone.label).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(offsetDescription(zone, at: date)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(index == 0 ? t("参考时区") : differenceDescription(comparison))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(index == 0 ? Color.green : Color.orange)
                        .padding(.horizontal, 5).padding(.vertical, 4)
                        .background((index == 0 ? Color.green : Color.orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                }
                HStack {
                    Text(time).font(.system(size: 14, weight: .semibold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer()
                    Label(t(copiedZone == zone.id ? "已复制" : "点击复制"), systemImage: copiedZone == zone.id ? "checkmark" : "square.on.square")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(.leading, 13)
            }.padding(.horizontal, 10).padding(.vertical, 7).contentShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(ClockRowStyle()).help(zone.id)
    }

    private func offsetDescription(_ zone: ClockZone, at date: Date) -> String {
        store.renderer.string(for: zone, at: date, format: "zzz (ZZZZ)")
    }

    private func differenceDescription(_ comparison: ZoneComparison) -> String {
        let seconds = abs(comparison.offsetSeconds)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let amount = minutes == 0 ? "\(hours)" : "\(hours):\(String(format: "%02d", minutes))"
        let prefix: String
        if store.settings.language == .english {
            prefix = comparison.offsetSeconds == 0 ? "Same time" : "\(amount)h \(comparison.offsetSeconds > 0 ? "ahead" : "behind")"
        } else {
            prefix = comparison.offsetSeconds == 0 ? "无时差" : "\(comparison.offsetSeconds > 0 ? "快" : "慢") \(hours) 小时\(minutes == 0 ? "" : " \(minutes) 分钟")"
        }
        let day: String
        switch comparison.dayDifference {
        case -1: day = t("昨天")
        case 0: day = ""
        case 1: day = t("明天")
        default: day = "\(comparison.dayDifference > 0 ? "+" : "")\(comparison.dayDifference)d"
        }
        return prefix + (day.isEmpty ? "" : " · " + day)
    }


}

private struct ClockRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverRow(content: configuration.label, pressed: configuration.isPressed)
    }
    private struct HoverRow<Content: View>: View {
        let content: Content
        let pressed: Bool
        @State private var hovered = false
        var body: some View {
            content.foregroundStyle(.primary)
                .background(Color.accentColor.opacity(pressed ? 0.17 : hovered ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 8))
                .onHover { hovered = $0 }
        }
    }
}

/// NSDatePicker receives its time zone explicitly; the macOS graphical SwiftUI
/// picker can otherwise display the system zone instead of the selected zone.
private struct ZonedDatePicker: NSViewRepresentable {
    @Binding var selection: Date
    let timeZone: TimeZone
    let locale: Locale
    let graphical: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = graphical ? .clockAndCalendar : .textFieldAndStepper
        picker.datePickerElements = graphical ? [.yearMonthDay] : [.hourMinute]
        picker.drawsBackground = false
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        return picker
    }
    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.parent = self
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        if picker.calendar != calendar { picker.calendar = calendar }
        if picker.locale != locale { picker.locale = locale }
        if picker.timeZone != timeZone { picker.timeZone = timeZone }
        if picker.dateValue != selection { picker.dateValue = selection }
    }
    final class Coordinator: NSObject {
        var parent: ZonedDatePicker
        init(_ parent: ZonedDatePicker) { self.parent = parent }
        @objc func changed(_ sender: NSDatePicker) { parent.selection = sender.dateValue }
    }
}
