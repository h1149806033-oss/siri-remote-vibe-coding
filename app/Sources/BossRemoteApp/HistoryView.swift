import BossRemoteCore
import BossRemoteUI
import SwiftUI

private enum HistoryFilter: String, CaseIterable, Identifiable {
    case all
    case button
    case voice
    case mapping

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return L10n.t("全部", "All")
        case .button: return L10n.t("按键", "Buttons")
        case .voice: return L10n.t("语音", "Voice")
        case .mapping: return L10n.t("映射", "Mappings")
        }
    }

    func includes(_ event: ActivityEvent) -> Bool {
        switch self {
        case .all:
            return true
        case .button:
            return event.kind == .button
        case .voice:
            return event.kind == .voice
        case .mapping:
            return event.kind == .mapping || event.kind == .app
        }
    }
}

private let historyLocale = Locale(
    identifier: L10n.usesChinese ? "zh_CN" : "en_US"
)

private struct HistoryDayGroup: Identifiable {
    let date: Date
    let events: [ActivityEvent]

    var id: Date { date }
}

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var history: HistoryStore
    @ObservedObject var settings: AppSettings
    @ObservedObject private var voiceStats: VoiceStatsStore
    @Environment(\.bossCompact) private var compact
    private let preview: Bool

    @State private var filter: HistoryFilter = .all
    @State private var confirmClear = false

    init(
        model: AppModel,
        history: HistoryStore,
        settings: AppSettings,
        preview: Bool = false
    ) {
        self._model = ObservedObject(wrappedValue: model)
        self._history = ObservedObject(wrappedValue: history)
        self._settings = ObservedObject(wrappedValue: settings)
        self._voiceStats = ObservedObject(wrappedValue: model.voiceStats)
        self.preview = preview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            overview
            filterBar
            timeline
        }
        .padding(.horizontal, BossMetrics.pageHorizontal)
        .padding(.top, BossMetrics.pageTop)
        .padding(.bottom, BossMetrics.pageBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert(
            L10n.t("清除记录？", "Clear records?"),
            isPresented: $confirmClear
        ) {
            Button(L10n.t("清除", "Clear"), role: .destructive) {
                model.clearHistory()
            }
            Button(L10n.t("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t(
                "本机的按键、语音会话和映射记录会被删除。",
                "Local button, voice-session and mapping records will be removed."
            ))
        }
    }

    private var header: some View {
        BossPageHeader(
            title: L10n.t("记录", "Records"),
            subtitle: L10n.t(
                "最近的按键、语音会话与映射变更",
                "Recent buttons, voice sessions and mapping changes"
            )
        ) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        settings.historyEnabled.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(
                                settings.historyEnabled
                                    ? BossTheme.accent
                                    : BossTheme.tertiary
                            )
                            .frame(width: 5, height: 5)
                            .shadow(
                                color: settings.historyEnabled
                                    ? BossTheme.accent.opacity(0.6)
                                    : .clear,
                                radius: 3
                            )
                        Text(L10n.t("记录", "Record"))
                            .font(BossTheme.label(10, weight: .medium))
                            .foregroundStyle(BossTheme.secondary)
                        Text(
                            settings.historyEnabled
                                ? L10n.t("开", "On")
                                : L10n.t("关", "Off")
                        )
                        .font(BossTheme.mono(9, weight: .medium))
                        .foregroundStyle(
                            settings.historyEnabled
                                ? BossTheme.accent
                                : BossTheme.tertiary
                        )
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(
                            settings.historyEnabled
                                ? BossTheme.accent.opacity(0.08)
                                : BossTheme.surface.opacity(0.8)
                        )
                    )
                    .overlay(
                        Capsule().stroke(
                            settings.historyEnabled
                                ? BossTheme.accent.opacity(0.22)
                                : BossTheme.hairline,
                            lineWidth: 1
                        )
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("记录开关", "Record toggle"))

                Button {
                    confirmClear = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(
                            history.events.isEmpty
                                ? BossTheme.tertiary.opacity(0.4)
                                : BossTheme.secondary
                        )
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(BossTheme.controlFill))
                        .overlay(Circle().stroke(BossTheme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(history.events.isEmpty)
                .help(L10n.t("清除记录", "Clear records"))
                .accessibilityLabel(L10n.t("清除记录", "Clear records"))
            }
        }
    }

    private var overview: some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 20) {
                    voiceTodayBlock
                    weekBlock
                }
            } else {
                HStack(alignment: .top, spacing: 36) {
                    voiceTodayBlock
                    Spacer(minLength: 24)
                    weekBlock
                }
            }
        }
    }

    private var voiceTodayBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("今日语音", "Voice today"))
                .font(BossTheme.label(10.5))
                .foregroundStyle(BossTheme.tertiary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(voiceDurationText(todayVoice.duration))
                    .font(BossTheme.display(32, weight: .bold))
                    .foregroundStyle(BossTheme.text)
                Text(sessionCountText(todayVoice.sessions))
                    .font(BossTheme.label(11))
                    .foregroundStyle(BossTheme.secondary)
            }
            yesterdayComparison
            HStack(spacing: 14) {
                miniStat(
                    L10n.t("今日按键", "Buttons"),
                    value: "\(todayButtonCount)"
                )
                BossSeparator()
                miniStat(
                    L10n.t("今日映射", "Mappings"),
                    value: "\(todayMappingCount)"
                )
            }
            .padding(.top, 3)
        }
    }

    private var weekBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("近 7 天语音", "Voice, last 7 days"))
                .font(BossTheme.label(9.5))
                .foregroundStyle(BossTheme.tertiary)
            VoiceWeekChart(days: weekDays, today: Date())
                .frame(height: 80)
            HStack(spacing: 0) {
                comparison(
                    L10n.t("昨天", "Yesterday"),
                    voiceDurationText(yesterdayVoice.duration)
                )
                comparison(
                    L10n.t("近 7 天", "7 days"),
                    voiceDurationText(weekTotal)
                )
                comparison(
                    L10n.t("日均", "Daily avg"),
                    voiceDurationText(weekAverage)
                )
                .help(L10n.t(
                    "按有语音记录的天数计算",
                    "Averaged over days with voice sessions"
                ))
            }
        }
        .frame(maxWidth: 500)
    }

    private var weekDays: [VoiceDay] {
        voiceStats.recentDays(7)
    }

    private var todayVoice: VoiceDay {
        weekDays.last ?? VoiceDay(
            day: Calendar.current.startOfDay(for: Date())
        )
    }

    private var yesterdayVoice: VoiceDay {
        guard weekDays.count > 1 else {
            return VoiceDay(day: Date())
        }
        return weekDays[weekDays.count - 2]
    }

    private var weekTotal: TimeInterval {
        weekDays.reduce(0) { $0 + $1.duration }
    }

    private var weekAverage: TimeInterval {
        let active = weekDays.filter { $0.sessions > 0 }
        guard !active.isEmpty else { return 0 }
        return weekTotal / Double(active.count)
    }

    private var yesterdayComparison: some View {
        Group {
            if yesterdayVoice.duration > 0 {
                let delta = todayVoice.duration - yesterdayVoice.duration
                HStack(spacing: 5) {
                    Text(L10n.t("比昨天", "vs yesterday"))
                        .font(BossTheme.label(10))
                        .foregroundStyle(BossTheme.tertiary)
                    Text(abs(delta) < 1
                        ? L10n.t("持平", "even")
                        : signedDurationText(delta))
                        .font(BossTheme.label(10.5, weight: .medium))
                        .foregroundStyle(
                            abs(delta) < 1
                                ? BossTheme.secondary
                                : (delta > 0
                                    ? BossTheme.accent
                                    : BossTheme.secondary)
                        )
                }
            } else if todayVoice.duration > 0 {
                Text(L10n.t("昨天没有语音记录", "No voice yesterday"))
                    .font(BossTheme.label(10))
                    .foregroundStyle(BossTheme.tertiary)
            } else {
                Text(L10n.t("今天还没有语音", "No voice today"))
                    .font(BossTheme.label(10))
                    .foregroundStyle(BossTheme.tertiary)
            }
        }
    }

    private func sessionCountText(_ count: Int) -> String {
        L10n.t(
            "\(count) 段",
            count == 1 ? "1 session" : "\(count) sessions"
        )
    }

    private func miniStat(_ title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(BossTheme.label(9.5))
                .foregroundStyle(BossTheme.tertiary)
            Text(value)
                .font(BossTheme.mono(11, weight: .medium))
                .foregroundStyle(BossTheme.secondary)
        }
    }

    private func comparison(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(BossTheme.label(9.5))
                .foregroundStyle(BossTheme.tertiary)
            Text(value)
                .font(BossTheme.mono(11.5, weight: .medium))
                .foregroundStyle(BossTheme.text)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(HistoryFilter.allCases) { item in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        filter = item
                    }
                } label: {
                    Text(item.title)
                        .font(BossTheme.label(10, weight: filter == item ? .semibold : .medium))
                        .foregroundStyle(
                            filter == item
                                ? BossTheme.accent
                                : BossTheme.secondary
                        )
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(
                                filter == item
                                    ? BossTheme.accent.opacity(0.11)
                                    : BossTheme.controlFill
                            )
                        )
                        .overlay(
                            Capsule().stroke(
                                filter == item
                                    ? BossTheme.accent.opacity(0.24)
                                    : BossTheme.hairline,
                                lineWidth: 1
                            )
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(filter == item ? .isSelected : [])
            }
            Spacer()
            Text(L10n.t(
                "\(filteredEvents.count) 条",
                filteredEvents.count == 1
                    ? "1 record"
                    : "\(filteredEvents.count) records"
            ))
            .font(BossTheme.mono(9.5, weight: .medium))
            .foregroundStyle(BossTheme.tertiary)
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            BossSectionHeader(
                icon: "clock.arrow.circlepath",
                title: L10n.t("时间线", "Timeline")
            ) {
                Text(L10n.t(
                    "只记录操作与会话，不保存语音内容",
                    "Operations only; no voice text is stored"
                ))
                .font(BossTheme.label(9.5))
                .foregroundStyle(BossTheme.tertiary)
            }
            .padding(.bottom, 10)

            BossRule()

            if filteredEvents.isEmpty {
                emptyState
            } else {
                timelineList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var timelineList: some View {
        if preview {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(dayGroups) { group in
                    dayHeader(group)
                    ForEach(group.events) { event in
                        eventRow(event)
                    }
                }
            }
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(dayGroups) { group in
                        dayHeader(group)
                        ForEach(group.events) { event in
                            eventRow(event)
                        }
                    }
                }
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if history.events.isEmpty {
                Image(systemName: "text.bubble")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(BossTheme.accent.opacity(0.8))
                Text(L10n.t("还没有记录", "No records yet"))
                    .font(BossTheme.display(15, weight: .semibold))
                    .foregroundStyle(BossTheme.text)
                Text(L10n.t(
                    "按下遥控器或说一句话，这里会出现你的操作轨迹。",
                    "Press the remote or speak once and your activity will appear here."
                ))
                .font(BossTheme.label(10.5))
                .foregroundStyle(BossTheme.tertiary)
                .multilineTextAlignment(.center)
            } else {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(BossTheme.tertiary)
                Text(L10n.t("没有符合条件的记录", "No matching records"))
                    .font(BossTheme.label(12, weight: .medium))
                    .foregroundStyle(BossTheme.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func dayHeader(_ group: HistoryDayGroup) -> some View {
        HStack(spacing: 8) {
            Text(dayLabel(group.date))
                .font(BossTheme.label(10, weight: .semibold))
                .foregroundStyle(BossTheme.secondary)
            Text("\(group.events.count)")
                .font(BossTheme.mono(9, weight: .medium))
                .foregroundStyle(BossTheme.tertiary)
            Rectangle()
                .fill(BossTheme.hairline)
                .frame(height: 1)
        }
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private func eventRow(_ event: ActivityEvent) -> some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(eventColor(event).opacity(0.10))
                Image(systemName: eventSymbol(event))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(eventColor(event))
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(eventTitle(event))
                        .font(BossTheme.label(11.5, weight: .medium))
                        .foregroundStyle(BossTheme.text)
                        .lineLimit(1)
                    if event.count > 1 {
                        Text("×\(event.count)")
                            .font(BossTheme.mono(9, weight: .semibold))
                            .foregroundStyle(BossTheme.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(BossTheme.accent.opacity(0.10)))
                    }
                    Spacer(minLength: 6)
                    Text(event.date.formatted(date: .omitted, time: .shortened))
                        .font(BossTheme.mono(9.5, weight: .medium))
                        .foregroundStyle(BossTheme.tertiary)
                }
                HStack(spacing: 5) {
                    if let appName = event.appName {
                        historyChip(appName, symbol: "app")
                    }
                    if let scope = event.scopeLabel, scope != event.appName {
                        historyChip(scope, symbol: nil)
                    }
                    if event.kind == .voice, let duration = event.duration {
                        Text(formatDuration(duration))
                            .font(BossTheme.label(9.5, weight: .medium))
                            .foregroundStyle(BossTheme.accent)
                        if let frames = event.frames, frames > 0 {
                            Text(L10n.t(
                                "\(frames) 帧",
                                "\(frames) frames"
                            ))
                            .font(BossTheme.label(9.5))
                            .foregroundStyle(BossTheme.tertiary)
                        }
                    }
                    if let detail = event.detail, event.kind == .mapping || event.kind == .app {
                        Text(detail)
                            .font(BossTheme.label(9.5))
                            .foregroundStyle(BossTheme.tertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BossTheme.hairline.opacity(0.7))
                .frame(height: 1)
                .padding(.leading, 39)
        }
    }

    private func historyChip(_ text: String, symbol: String?) -> some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 7, weight: .semibold))
            }
            Text(text)
                .font(BossTheme.label(9.5))
        }
        .foregroundStyle(BossTheme.tertiary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(BossTheme.controlFill))
    }

    private func eventTitle(_ event: ActivityEvent) -> String {
        switch event.kind {
        case .button:
            let control = event.control?.title ?? L10n.t("按键", "Button")
            return "\(control) → \(event.actionLabel ?? L10n.t("不执行操作", "No action"))"
        case .voice:
            return L10n.t("语音会话", "Voice session")
        case .mapping:
            let control = event.control?.title ?? L10n.t("按键", "Button")
            return "\(control) → \(event.actionLabel ?? "")"
        case .app:
            return L10n.t(
                "切换到 \(event.appName ?? "App")",
                "Switched to \(event.appName ?? "App")"
            )
        }
    }

    private func eventSymbol(_ event: ActivityEvent) -> String {
        switch event.kind {
        case .voice: return "waveform"
        case .mapping: return "arrow.left.arrow.right"
        case .app: return "app"
        case .button:
            guard let control = event.control else { return "button.programmable" }
            switch control {
            case .power: return "power"
            case .up: return "chevron.up"
            case .down: return "chevron.down"
            case .left: return "chevron.left"
            case .right: return "chevron.right"
            case .select: return "circle.circle"
            case .back: return "chevron.backward"
            case .tv: return "tv"
            case .playPause: return "playpause"
            case .volumeUp: return "speaker.plus"
            case .volumeDown: return "speaker.minus"
            case .mute: return "speaker.slash"
            case .siri: return "waveform"
            case .ringUp, .ringDown, .ringLeft, .ringRight:
                return "arrow.triangle.2.circlepath"
            case .swipeUp, .swipeDown, .swipeLeft, .swipeRight:
                return "hand.draw"
            case .tapTwo: return "hand.tap"
            }
        }
    }

    private func eventColor(_ event: ActivityEvent) -> Color {
        switch event.kind {
        case .voice: return BossTheme.accentBright
        case .mapping: return BossTheme.accent
        case .app: return BossTheme.success
        case .button: return BossTheme.secondary
        }
    }

    private var filteredEvents: [ActivityEvent] {
        history.events
            .filter { filter.includes($0) }
            .sorted { $0.date > $1.date }
    }

    private var dayGroups: [HistoryDayGroup] {
        let calendar = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [ActivityEvent]] = [:]
        for event in filteredEvents {
            let day = calendar.startOfDay(for: event.date)
            if buckets[day] == nil {
                order.append(day)
                buckets[day] = []
            }
            buckets[day]?.append(event)
        }
        return order.map { day in
            HistoryDayGroup(date: day, events: buckets[day] ?? [])
        }
    }

    private var todayEvents: [ActivityEvent] {
        history.events.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var todayButtonCount: Int {
        todayEvents
            .filter { $0.kind == .button }
            .reduce(0) { $0 + $1.count }
    }

    private var todayVoiceEvents: [ActivityEvent] {
        todayEvents.filter { $0.kind == .voice }
    }

    private var todayVoiceDuration: TimeInterval {
        todayVoiceEvents.compactMap(\.duration).reduce(0, +)
    }

    private var todayMappingCount: Int {
        todayEvents.filter { $0.kind == .mapping || $0.kind == .app }.count
    }

    private func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return L10n.t("今天", "Today")
        }
        if calendar.isDateInYesterday(date) {
            return L10n.t("昨天", "Yesterday")
        }
        return date.formatted(
            .dateTime.month().day().weekday(.abbreviated)
                .locale(historyLocale)
        )
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(
                format: L10n.t("%.1f 秒", "%.1fs"),
                duration
            )
        }
        let seconds = Int(duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct VoiceWeekChart: View {
    let days: [VoiceDay]
    let today: Date

    var body: some View {
        let calendar = Calendar.current
        let maxDuration = max(60, days.map(\.duration).max() ?? 0)
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days) { day in
                    let isToday = calendar.isDate(
                        day.day,
                        inSameDayAs: today
                    )
                    let fraction = CGFloat(
                        min(max(day.duration / maxDuration, 0), 1)
                    )
                    VStack {
                        Spacer(minLength: 0)
                        UnevenRoundedRectangle(
                            topLeadingRadius: 3,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 3,
                            style: .continuous
                        )
                        .fill(
                            day.duration > 0
                                ? (isToday
                                    ? BossTheme.accent
                                    : BossTheme.accent.opacity(0.35))
                                : BossTheme.hairline
                        )
                        .frame(height: max(2, 56 * fraction))
                    }
                    .frame(maxWidth: .infinity)
                    .help(
                        "\(fullLabel(for: day.day, calendar: calendar)) " +
                        voiceDurationText(day.duration)
                    )
                    .accessibilityLabel(
                        "\(fullLabel(for: day.day, calendar: calendar)) " +
                        voiceDurationText(day.duration)
                    )
                }
            }
            .frame(height: 56)

            BossRule(opacity: 0.7)

            HStack(spacing: 8) {
                ForEach(days) { day in
                    let isToday = calendar.isDate(
                        day.day,
                        inSameDayAs: today
                    )
                    Text(shortLabel(for: day.day, calendar: calendar))
                        .font(BossTheme.label(
                            8.5,
                            weight: isToday ? .semibold : .medium
                        ))
                        .foregroundStyle(
                            isToday ? BossTheme.accent : BossTheme.tertiary
                        )
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 5)
        }
        .frame(height: 80)
    }

    private func shortLabel(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) {
            return L10n.t("今天", "Today")
        }
        if calendar.isDateInYesterday(date) {
            return L10n.t("昨天", "Yest.")
        }
        return date.formatted(
            .dateTime.weekday(.abbreviated).locale(historyLocale)
        )
    }

    private func fullLabel(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) {
            return L10n.t("今天", "Today")
        }
        if calendar.isDateInYesterday(date) {
            return L10n.t("昨天", "Yesterday")
        }
        return date.formatted(
            .dateTime.month().day().weekday(.abbreviated)
                .locale(historyLocale)
        )
    }
}

private func voiceDurationText(_ duration: TimeInterval) -> String {
    let total = Int(max(0, duration.rounded()))
    if total >= 3600 {
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return L10n.t(
            "\(hours) 小时 \(String(format: "%02d", minutes)) 分",
            "\(hours)h \(String(format: "%02d", minutes))m"
        )
    }
    if total >= 60 {
        let minutes = total / 60
        let seconds = total % 60
        return L10n.t(
            "\(minutes) 分 \(String(format: "%02d", seconds)) 秒",
            "\(minutes)m \(String(format: "%02d", seconds))s"
        )
    }
    return L10n.t("\(total) 秒", "\(total)s")
}

private func signedDurationText(_ duration: TimeInterval) -> String {
    let sign = duration >= 0 ? "+" : "−"
    return sign + voiceDurationText(abs(duration))
}
