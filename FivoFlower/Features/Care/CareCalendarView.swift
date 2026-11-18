import SwiftUI

struct CareCalendarView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var selectedDate = Date()
    @State private var displayedMonth = FivoDate.monthStart(Date())
    @State private var reminders: [CareReminder] = []
    @State private var plantNames: [UUID: String] = [:]
    @State private var errorMessage: String?

    private var selectedReminders: [CareReminder] {
        CareCalendarCalculator.pendingReminders(
            on: selectedDate,
            reminders: reminders,
            calendar: env.calendar
        )
    }

    private var calendarDays: [CareCalendarDay] {
        CareCalendarCalculator.days(
            forMonthContaining: displayedMonth,
            reminders: reminders,
            calendar: env.calendar
        )
    }

    private var weekdayTitles: [String] {
        let symbols = env.calendar.shortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(env.calendar.firstWeekday - 1 + $0) % 7] }
    }

    private let calendarColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FivoSpacing.md) {
                    monthCalendar
                        .accessibilityIdentifier("care.calendar")

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(FivoDate.day(selectedDate))
                                .font(FivoFont.sectionTitle)
                                .foregroundStyle(FivoColor.textPrimary)
                            Text("待办 \(selectedReminders.count) 项")
                                .font(FivoFont.caption)
                                .foregroundStyle(FivoColor.textSecondary)
                        }
                        Spacer()
                        if env.calendar.isDateInToday(selectedDate) == false {
                            Button("回到今天") { select(Date()) }
                                .font(FivoFont.captionStrong)
                                .foregroundStyle(FivoColor.textPrimary)
                        }
                    }

                    if let errorMessage {
                        ErrorStateView(message: errorMessage) { load() }
                    } else if selectedReminders.isEmpty {
                        EmptyStateView(
                            systemImage: "calendar.badge.checkmark",
                            title: "当日没有待办",
                            message: "可从植物详情的当前养护状态中设置周期。"
                        )
                    } else {
                        ForEach(selectedReminders) { reminder in
                            reminderCard(reminder)
                        }
                    }
                }
                .fivoPagePadding()
                .padding(.bottom, 110)
            }
            .background(FivoColor.surfaceBase)
            .navigationTitle("养护日历")
            .navigationBarTitleDisplayMode(.large)
            .task { load() }
            .onChange(of: env.dataRevision) { _, _ in load() }
        }
    }

    private var monthCalendar: some View {
        VStack(spacing: FivoSpacing.sm) {
            HStack {
                Button {
                    moveMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 36)
                }
                .accessibilityLabel("上个月")
                .accessibilityIdentifier("calendar.previousMonth")
                Spacer()
                Text(FivoDate.yearMonthFormatter.string(from: displayedMonth))
                    .font(FivoFont.cardTitle)
                    .foregroundStyle(FivoColor.textPrimary)
                Spacer()
                Button {
                    moveMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 44, height: 36)
                }
                .accessibilityLabel("下个月")
                .accessibilityIdentifier("calendar.nextMonth")
            }
            .foregroundStyle(FivoColor.textPrimary)

            LazyVGrid(columns: calendarColumns, spacing: 4) {
                ForEach(weekdayTitles, id: \.self) { weekday in
                    Text(weekday)
                        .font(FivoFont.captionStrong)
                        .foregroundStyle(FivoColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 24)
                }

                ForEach(calendarDays) { day in
                    let isSelected = env.calendar.isDate(day.date, inSameDayAs: selectedDate)
                    let isToday = env.calendar.isDateInToday(day.date)
                    Button {
                        select(day.date)
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(day.dayNumber)")
                                .font(FivoFont.callout.weight(isSelected ? .bold : .regular))
                            if day.pendingCount > 0 {
                                Text("\(day.pendingCount) 项")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(FivoColor.danger)
                                    .accessibilityIdentifier("calendar.pendingCount.\(FivoDate.day(day.date))")
                            } else {
                                Text(" ")
                                    .font(.system(size: 9))
                                    .accessibilityHidden(true)
                            }
                        }
                        .foregroundStyle(FivoColor.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isSelected
                                      ? FivoColor.accentStart.opacity(0.65)
                                      : day.pendingCount > 0
                                      ? FivoColor.danger.opacity(0.08)
                                      : Color.clear)
                        }
                        .overlay {
                            if isToday {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(FivoColor.accentEnd, lineWidth: isSelected ? 0 : 1)
                            }
                        }
                        .opacity(day.isInDisplayedMonth ? 1 : 0.35)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(FivoDate.day(day.date))，\(day.pendingCount) 项待办")
                    .accessibilityIdentifier("calendar.day.\(FivoDate.day(day.date))")
                }
            }
        }
        .padding(FivoSpacing.sm)
        .softCard(padding: 0)
    }

    private func reminderCard(_ reminder: CareReminder) -> some View {
        VStack(alignment: .leading, spacing: FivoSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reminder.title)
                        .font(FivoFont.cardTitle)
                        .foregroundStyle(FivoColor.textPrimary)
                    Text(plantNames[reminder.plantID] ?? "植物档案已删除")
                        .font(FivoFont.callout)
                        .foregroundStyle(FivoColor.textSecondary)
                    Label(FivoDate.dateTime(reminder.dueAt), systemImage: "clock")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                    Text(reminder.recurrence.title)
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                }
                Spacer()
                StatusPill(text: "待处理", systemImage: "circle", tint: FivoColor.accentEnd)
            }

            HStack(spacing: FivoSpacing.sm) {
                Button {
                    complete(reminder)
                } label: {
                    Label("完成", systemImage: "checkmark")
                        .font(FivoFont.captionStrong)
                        .foregroundStyle(FivoColor.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(FivoColor.accentStart.opacity(0.6), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("calendar.complete.\(reminder.id.uuidString)")

            }
        }
        .softCard()
    }

    private func moveMonth(by offset: Int) {
        displayedMonth = env.calendar.date(byAdding: .month, value: offset, to: displayedMonth) ?? displayedMonth
    }

    private func select(_ date: Date) {
        selectedDate = date
        displayedMonth = FivoDate.monthStart(date, calendar: env.calendar)
    }

    private func load() {
        do {
            reminders = try env.reminders.reminders()
            let plants = try env.plants.fetchPlants()
            plantNames = Dictionary(uniqueKeysWithValues: plants.map { ($0.id, $0.name) })
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func complete(_ reminder: CareReminder) {
        do {
            _ = try env.reminders.completeReminder(id: reminder.id, at: Date(), createCareRecord: true)
            Task { await env.reconcileNotifications() }
            env.showToast("已完成提醒并记录养护")
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}
