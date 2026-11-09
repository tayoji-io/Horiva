import AppKit
import SwiftUI
import ClockCore
import ServiceManagement

struct ZoneLabelField: View {
    let label: String
    let language: ClockLanguage
    let onCommit: (String) -> Void
    @State private var draft: String
    @FocusState private var editing: Bool

    init(label: String, language: ClockLanguage, onCommit: @escaping (String) -> Void) {
        self.label = label
        self.language = language
        self.onCommit = onCommit
        _draft = State(initialValue: label)
    }

    var body: some View {
        TextField(language.localized("显示名称"), text: Binding(
            get: { draft },
            set: { value in draft = value; onCommit(value) }
        ))
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
            .focused($editing)
            .onSubmit { commit() }
            .onChange(of: editing) { focused in if !focused { commit() } }
            .onChange(of: label) { value in if !editing { draft = value } }
    }

    private func commit() {
        onCommit(draft)
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = trimmed.isEmpty ? label : String(trimmed.prefix(24))
    }
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    let onPreview: () -> Void
    let onDone: () -> Void
    @State private var search = ""
    @State private var selectedZone = "Asia/Tokyo"
    @State private var customFormat = ""
    @State private var confirmReset = false
    @State private var sampleDate = Date()
    private let formats = [("24 小时", "HH:mm"), ("24 小时 + 秒", "HH:mm:ss"), ("12 小时", "h:mm a"), ("12 小时 + 秒", "h:mm:ss a"), ("日期 + 时间", "MM/dd HH:mm"), ("日期 + 星期 + 时间", "MM/dd EEE HH:mm")]
    private let presets = [("极简时间", "HH:mm"), ("常用标准", "MM-dd EEE HH:mm"), ("详细全量", "yyyy-MM-dd HH:mm:ss"), ("12 小时制", "h:mm a")]
    private let aliases = ["Asia/Shanghai": "上海 北京 中国", "America/Los_Angeles": "洛杉矶 旧金山 美国 西雅图", "America/New_York": "纽约 美国", "Europe/London": "伦敦 英国", "Asia/Tokyo": "东京 日本", "Asia/Hong_Kong": "香港", "Asia/Singapore": "新加坡", "Europe/Paris": "巴黎 法国", "Australia/Sydney": "悉尼 澳大利亚", "Asia/Taipei": "台北 台湾", "Asia/Seoul": "首尔 韩国", "Asia/Kolkata": "印度 加尔各答", "Europe/Berlin": "柏林 德国", "UTC": "协调世界时"]

    private var available: [String] {
        Array(Set(TimeZone.knownTimeZoneIdentifiers + ["UTC"])).sorted().filter { id in
            !store.settings.zones.contains(where: { $0.id == id }) &&
            (search.isEmpty || "\(id) \(aliases[id] ?? "") \(TimeZone(identifier: id)?.localizedName(for: .standard, locale: Locale(identifier: "zh_CN")) ?? "")".localizedCaseInsensitiveContains(search))
        }
    }

    private func t(_ text: String) -> String { store.settings.language.localized(text) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    previewSection
                    zonesSection
                    formatSection
                    runtimeSection
                }.padding(24)
            }
            footer
        }
        .font(.system(size: 12))
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 720, minHeight: 540)
        .onAppear { customFormat = store.settings.format; store.refreshLoginStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.refreshLoginStatus() }
        .onChange(of: search) { _ in if !available.contains(selectedZone) { selectedZone = available.first ?? "" } }
        .alert(t("恢复默认设置？"), isPresented: $confirmReset) {
            Button(t("取消"), role: .cancel) {}
            Button(t("恢复默认"), role: .destructive) {
                store.restoreDefaults()
                customFormat = store.settings.format
                selectedZone = available.first ?? ""
            }
        } message: { Text(t("将恢复默认时区、时间格式和字体。")) }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "menubar.rectangle").foregroundStyle(Color.accentColor)
                Text(t("状态栏实时预览")).fontWeight(.semibold)
                badge(t("实时同步"), color: .blue)
                Button(store.settings.language == .english ? "Preview Menu" : "预览下拉菜单", action: onPreview).buttonStyle(.borderless).font(.system(size: 10))
                Spacer()
                Circle().fill(.green).frame(width: 5, height: 5)
                Text(t("与菜单栏同步")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(t("状态栏外观效果")).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                ScrollView(.horizontal, showsIndicators: false) {
                    ClockPreviewText(store: store)
                        .fixedSize()
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.17)))
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.16, green: 0.17, blue: 0.19), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var zonesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("已选时区列表")).font(.system(size: 13, weight: .semibold))
                    Text(t("按由左至右顺序在菜单栏排列，使用箭头调整排序"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                badge(store.settings.language == .english ? "\(store.settings.zones.count) zones" : "已添加 \(store.settings.zones.count) 个时区", color: .blue)
            }
            VStack(spacing: 9) {
                ForEach(Array(store.settings.zones.enumerated()), id: \.element.id) { index, zone in
                    zoneRow(zone, index: index)
                }
            }
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(t("搜索城市、国家或时区"), text: $search).textFieldStyle(.plain)
                }.padding(8).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                Picker(t("添加时区"), selection: $selectedZone) {
                    Text(t(available.isEmpty ? "没有匹配的时区" : "请选择时区")).tag("")
                    ForEach(available, id: \.self) { id in
                        Text("\(id.replacingOccurrences(of: "_", with: " "))\(store.settings.language == .english ? "" : (aliases[id]?.split(separator: " ").first.map { " · " + $0 } ?? ""))").tag(id)
                    }
                }.labelsHidden().frame(width: 240)
                Button(action: addZone) { Label(t("添加时区"), systemImage: "plus") }
                    .buttonStyle(.borderedProminent).disabled(!available.contains(selectedZone))
            }.padding(8).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
        }
    }

    private func zoneRow(_ zone: ClockZone, index: Int) -> some View {
        HStack(spacing: 12) {
            Circle().fill(index == 0 ? Color.green : Color.blue).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 4) {
                ZoneLabelField(label: zone.label, language: store.settings.language) { value in
                    store.update { settings in
                        if let i = settings.zones.firstIndex(where: { $0.id == zone.id }) { settings.zones[i].label = value }
                    }
                }.frame(maxWidth: 190)
                Text(zone.id).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).help(zone.id)
            }.frame(maxWidth: .infinity, alignment: .leading)
            TimelineView(.everyMinute) { context in
                VStack(alignment: .trailing, spacing: 5) {
                    Text(store.settings.timeZone(for: zone).abbreviation(for: context.date) ?? zone.id)
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(hourText(zone, at: context.date)).font(.system(size: 12, weight: .medium, design: .monospaced))
                }
            }.frame(width: 65)
            Divider().frame(height: 32)
            Toggle(t("显示时区"), isOn: Binding(
                get: { store.settings.zones.first(where: { $0.id == zone.id })?.showLabel ?? true },
                set: { value in
                    store.update { settings in
                        if let i = settings.zones.firstIndex(where: { $0.id == zone.id }) { settings.zones[i].showLabel = value }
                    }
                }
            ))
            .toggleStyle(.switch).controlSize(.small)
            .help(t("关闭后只隐藏名称，仍显示这个时区的时间"))
            .accessibilityLabel("\(zone.label): \(t("显示时区"))")
            HStack(spacing: 2) {
                Button { move(zone.id, by: -1) } label: { Image(systemName: "chevron.up").frame(width: 20, height: 24) }
                    .disabled(index == 0).help(t("向左移动")).accessibilityLabel(t("向左移动") + " " + zone.label)
                Button { move(zone.id, by: 1) } label: { Image(systemName: "chevron.down").frame(width: 20, height: 24) }
                    .disabled(index == store.settings.zones.count - 1).help(t("向右移动")).accessibilityLabel(t("向右移动") + " " + zone.label)
                Button { store.update { $0.zones.removeAll { $0.id == zone.id } } } label: { Image(systemName: "minus.circle").frame(width: 24, height: 24) }
                    .disabled(store.settings.zones.count == 1).help(t("删除时区")).accessibilityLabel(t("删除时区") + " " + zone.label)
            }.buttonStyle(.borderless).foregroundStyle(.secondary)
        }.padding(12).settingsCard()
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(t("显示与排版定制")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(t("自定义格式与字体")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text(t("时间格式预设")).fontWeight(.medium)
                Spacer()
                Menu(t("更多预设")) {
                    ForEach(formats, id: \.1) { name, pattern in
                        Button(t(name)) { setFormat(pattern) }
                    }
                }.menuStyle(.borderlessButton).fixedSize()
            }
            HStack(spacing: 8) {
                ForEach(presets, id: \.1) { name, pattern in
                    presetButton(name, pattern: pattern, at: sampleDate)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(t("自定义时间格式表达式")).fontWeight(.medium)
                    Spacer()
                    Text(t("Unicode 日期格式")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    TextField(t("例如 yyyy-MM-dd HH:mm:ss"), text: $customFormat)
                        .font(.system(size: 12, design: .monospaced)).textFieldStyle(.roundedBorder)
                        .onSubmit { applyFormat() }
                    Button(t("应用修改")) { applyFormat() }
                        .disabled(customFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text(t("HH：24 小时    h：12 小时    mm：分钟    ss：秒    a：AM/PM\nyyyy：年    MM-dd：月-日    EEE：星期    '文字'：原样显示"))
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
            }
            Divider()
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("菜单栏字体选择")).fontWeight(.medium)
                    Text(t("等宽字体让时间显示更整齐")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Picker(t("菜单栏字体选择"), selection: Binding(get: { store.settings.font }, set: { value in
                    store.update { $0.font = value }
                })) {
                    Text(t("系统字体（数字等宽）")).tag(ClockFont.system)
                    Text(t("系统等宽字体")).tag(ClockFont.monospaced)
                }.labelsHidden().frame(width: 300)
            }
            HStack {
                Text(t("分隔符样式")).fontWeight(.medium)
                Spacer()
                Picker(t("分隔符样式"), selection: Binding(
                    get: { store.settings.separator },
                    set: { value in store.update { $0.separator = value } }
                )) {
                    Text(t("中圆点 ·（默认）")).tag(ClockSeparator.dot)
                    Text(t("竖线 |")).tag(ClockSeparator.pipe)
                    Text(t("短横线 -")).tag(ClockSeparator.dash)
                    Text(t("双空格")).tag(ClockSeparator.space)
                }.labelsHidden().frame(width: 300)
            }
        }.padding(16).settingsCard()
    }

    private func presetButton(_ name: String, pattern: String, at date: Date) -> some View {
        let selected = store.settings.format == pattern
        let example = store.renderer.string(for: store.settings.zones[0], at: date, format: pattern)
        return Button { setFormat(pattern) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(t(name)).font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 10)) }
                }
                Text(example).font(.system(size: 9, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.8)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
            .foregroundStyle(selected ? Color.accentColor : .primary)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.06) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 1.5 : 1))
        }.buttonStyle(.plain).help(pattern).accessibilityLabel("\(t(name)), \(example)")
    }

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t("系统与启动首选项")).font(.system(size: 13, weight: .semibold))
            Divider()
            Toggle(t("登录 macOS 时自动启动 Horiva"), isOn: Binding(
                get: { store.loginStatus == .enabled },
                set: { store.setLaunchAtLogin($0) }
            ))
            if store.loginStatus == .requiresApproval {
                HStack {
                    Text(t("需要在系统设置中允许登录项")).foregroundStyle(.orange)
                    Button(t("打开登录项设置")) { SMAppService.openSystemSettingsLoginItems() }
                    Button(t("取消启动申请")) { store.setLaunchAtLogin(false) }
                }.font(.system(size: 11))
            }
            if let error = store.serviceError {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("无法更新登录项") + ": " + error).foregroundStyle(.red)
                        Text(t("先将 Horiva 移入“应用程序”，再启用开机启动。")).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(t("关闭")) { store.serviceError = nil }
                }.font(.system(size: 11))
            }
            Toggle(t("自动处理夏令时（DST）切换"), isOn: Binding(
                get: { store.settings.automaticallyAdjustDST },
                set: { enabled in store.update { $0.setAutomaticallyAdjustDST(enabled) } }
            ))
            Text(t("关闭后固定各时区当前 UTC 偏移；重新开启后恢复自动切换。"))
                .font(.system(size: 10)).foregroundStyle(.secondary).padding(.leading, 20)
            Toggle(t("在系统菜单中显示日历入口"), isOn: Binding(
                get: { store.settings.showCalendar },
                set: { enabled in store.update { $0.showCalendar = enabled } }
            ))
            Text(t("日历和换算在独立窗口打开，关闭后停止刷新。"))
                .font(.system(size: 10)).foregroundStyle(.secondary).padding(.leading, 20)
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("界面语言 (Language)")).fontWeight(.medium)
                    Text(t("选择界面与时间描述的默认语言"))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Picker(t("界面语言 (Language)"), selection: Binding(
                    get: { store.settings.language },
                    set: { language in store.update { $0.language = language } }
                )) {
                    Text("简体中文").tag(ClockLanguage.simplifiedChinese)
                    Text("English (US)").tag(ClockLanguage.english)
                }.labelsHidden().frame(width: 210)
            }
        }.toggleStyle(.checkbox).frame(maxWidth: .infinity, alignment: .leading).padding(16).settingsCard()
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text(t("设置自动保存 · 不修改系统时区")).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button(t("恢复默认")) { confirmReset = true }.controlSize(.large)
                Button(t("完成"), action: onDone).buttonStyle(.borderedProminent).controlSize(.large)
            }.padding(.horizontal, 24).padding(.vertical, 14)
        }.background(Color(nsColor: .windowBackgroundColor))
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.08), in: Capsule())
    }
    private func hourText(_ zone: ClockZone, at date: Date) -> String {
        store.renderer.string(for: zone, at: date, format: "HH:mm")
    }
    private func addZone() {
        guard available.contains(selectedZone) else { return }
        let id = selectedZone
        let label = store.settings.language == .english ? String(id.split(separator: "/").last ?? "UTC").replacingOccurrences(of: "_", with: " ") : aliases[id]?.split(separator: " ").first.map(String.init) ?? String(id.split(separator: "/").last ?? "UTC").replacingOccurrences(of: "_", with: " ")
        store.update { $0.zones.append(ClockZone(id: id, label: label)) }
        selectedZone = available.first ?? ""
    }
    private func move(_ id: String, by offset: Int) {
        store.update { settings in
            guard let i = settings.zones.firstIndex(where: { $0.id == id }), settings.zones.indices.contains(i + offset) else { return }
            settings.zones.swapAt(i, i + offset)
        }
    }
    private func setFormat(_ pattern: String) {
        store.update { $0.format = pattern }
        customFormat = store.settings.format
    }
    private func applyFormat() {
        guard !customFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        setFormat(customFormat)
    }
}

private extension View {
    func settingsCard() -> some View {
        self.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.025), radius: 2, y: 1)
    }
}
