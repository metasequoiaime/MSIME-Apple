import SwiftUI

struct TypingStatisticsView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var statistics = TypingStatistics()
  @State private var errorMessage = ""
  @State private var confirmsReset = false
  private let store = TypingStatisticsStore()
  private var dates: [Date] {
    (0..<7).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }
  }

  var body: some View {
    Form {
      Section {
        HStack {
          metric("今日输入", count: statistics.count(on: Date()), identifier: "typingToday")
          Spacer()
          metric("累计输入", count: statistics.total, identifier: "typingTotal")
        }.padding(.vertical, 12)
      }
      Section("近 7 天") {
        ForEach(dates, id: \.self) { date in
          HStack {
            Text(date, format: .dateTime.month().day()).frame(width: 65, alignment: .leading)
            GeometryReader { geometry in
              Capsule().fill(MetasequoiaTheme.forest.opacity(0.75))
                .frame(width: geometry.size.width * fraction(for: date), height: 8)
                .frame(maxHeight: .infinity)
            }.frame(height: 24).accessibilityHidden(true)
            Text("\(statistics.count(on: date)) 字").monospacedDigit()
              .frame(minWidth: 50, alignment: .trailing)
          }
        }
      }
      Section {
        Toggle("记录打字统计", isOn: Binding(get: { statistics.enabled }, set: { enabled in
          update { try store.setEnabled(enabled) }
        })).accessibilityIdentifier("typingStatisticsEnabled")
        Button("刷新统计") { reload() }
        Button("清空统计", role: .destructive) { confirmsReset = true }
          .accessibilityIdentifier("resetTypingStatistics")
      } footer: {
        Text("仅统计水杉键盘提交的字符，含标点及表情，不含空格、换行和未上屏拼音。删除文字不扣减累计值。统计从启用后开始，不补算历史输入。仅在本机保存每日字数，不保存输入内容。")
      }
      Section("开启统计") {
        Text("请在系统设置 → 通用 → 键盘 → 键盘 → 水杉输入法中开启“允许完全访问”，以便键盘将字数写入本机统计。未开启时仍可正常打字，但不会记录统计。")
        Button("前往系统设置") {
          guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
          UIApplication.shared.open(url)
        }
      }
      if !errorMessage.isEmpty { Section { Text(errorMessage).foregroundStyle(.secondary) } }
    }
    .navigationTitle("打字统计")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { reload() }
    .onChange(of: scenePhase) { if $0 == .active { reload() } }
    .alert("清空所有打字统计？", isPresented: $confirmsReset) {
      Button("取消", role: .cancel) {}
      Button("清空", role: .destructive) { update { try store.reset() } }
    } message: { Text("累计字数和每日记录将被删除，无法恢复。") }
  }

  private func fraction(for date: Date) -> Double {
    Double(statistics.count(on: date)) / Double(max(1, dates.map { statistics.count(on: $0) }.max() ?? 1))
  }

  private func metric(_ title: String, count: Int, identifier: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.subheadline).foregroundStyle(.secondary)
      Text("\(count)").font(.system(size: 32, weight: .semibold, design: .rounded))
        .foregroundStyle(MetasequoiaTheme.forest).accessibilityIdentifier(identifier)
      Text("字").font(.caption).foregroundStyle(.secondary)
    }
  }

  private func reload() { update {} }
  private func update(_ operation: () throws -> Void) {
    do {
      try operation()
      statistics = try store.load()
      errorMessage = ""
    } catch { errorMessage = "暂时无法读取或保存统计，请解锁设备后重试。" }
  }
}
