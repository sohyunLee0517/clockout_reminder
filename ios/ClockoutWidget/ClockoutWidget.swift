//
//  ClockoutWidget.swift
//  ClockoutWidget
//
//  출근/퇴근 버튼 홈 위젯 (iOS 17+ 인터랙티브)
//

import AppIntents
import SwiftUI
import WidgetKit
import home_widget

// ⚠️ Flutter 의 appGroupId 와 반드시 동일해야 함
private let widgetGroupId = "group.com.isohyeon.clockoutReminder"

// MARK: - Timeline Entry

struct ClockoutEntry: TimelineEntry {
  let date: Date
  let status: String
  let subtitle: String
}

struct ClockoutProvider: TimelineProvider {
  func placeholder(in context: Context) -> ClockoutEntry {
    ClockoutEntry(date: Date(), status: "출근 전", subtitle: "출근 버튼을 눌러 시작하세요")
  }

  func getSnapshot(in context: Context, completion: @escaping (ClockoutEntry) -> Void) {
    completion(readEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<ClockoutEntry>) -> Void) {
    completion(Timeline(entries: [readEntry()], policy: .atEnd))
  }

  private func readEntry() -> ClockoutEntry {
    let data = UserDefaults(suiteName: widgetGroupId)
    return ClockoutEntry(
      date: Date(),
      status: data?.string(forKey: "status") ?? "출근 전",
      subtitle: data?.string(forKey: "subtitle") ?? "출근 버튼을 눌러 시작하세요"
    )
  }
}

// MARK: - 버튼 동작 (App Intent → Flutter 백그라운드 콜백)

@available(iOS 17, *)
struct ClockoutActionIntent: AppIntent {
  static var title: LocalizedStringResource = "출퇴근 체크"

  @Parameter(title: "URL")
  var url: String

  init() {}
  init(url: String) { self.url = url }

  func perform() async throws -> some IntentResult {
    await HomeWidgetBackgroundWorker.run(
      url: URL(string: url),
      appGroup: widgetGroupId
    )
    return .result()
  }
}

// MARK: - View

struct ClockoutWidgetEntryView: View {
  var entry: ClockoutProvider.Entry

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(entry.status)
        .font(.headline)
        .bold()
      Text(entry.subtitle)
        .font(.caption)
        .foregroundColor(.secondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: 6)

      if #available(iOSApplicationExtension 17, *) {
        HStack(spacing: 8) {
          Button(intent: ClockoutActionIntent(url: "clockoutwidget://checkin")) {
            Text("출근").frame(maxWidth: .infinity)
          }
          .tint(Color.blue.opacity(0.2))
          .foregroundColor(.primary)

          Button(intent: ClockoutActionIntent(url: "clockoutwidget://checkout")) {
            Text("퇴근").frame(maxWidth: .infinity)
          }
          .tint(.blue)
          .foregroundColor(.white)
        }
        .font(.subheadline.bold())
        .buttonBorderShape(.roundedRectangle(radius: 10))
      } else {
        Text("iOS 17 이상에서 버튼을 사용할 수 있어요")
          .font(.caption2)
          .foregroundColor(.secondary)
      }
    }
  }
}

// MARK: - Widget

@main
struct ClockoutWidget: Widget {
  let kind: String = "ClockoutWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: ClockoutProvider()) { entry in
      if #available(iOSApplicationExtension 17.0, *) {
        ClockoutWidgetEntryView(entry: entry)
          .containerBackground(.fill.tertiary, for: .widget)
      } else {
        ClockoutWidgetEntryView(entry: entry)
          .padding()
      }
    }
    .configurationDisplayName("퇴근 알림")
    .description("출근/퇴근을 바로 체크하는 위젯")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
