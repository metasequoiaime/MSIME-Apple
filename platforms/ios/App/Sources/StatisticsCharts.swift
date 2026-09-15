import Charts
import SwiftUI

/// 统计页的四张图。
///
/// 四个标签原来画的是同一种东西:一条按比例分段的长条,加一列数字。一屏之内换四次标签、看四次同样的形状,等于没换。每一块现在按它自己的问题选图形 —— 趋势是时间,用折线和日历热力图;类型和模式是「占了多大一块」,用饼图和环形图;方案是「谁多谁少」,用横向排行。
///
/// 图形本身交给 Swift Charts(iOS 16 起),不自己画路径:轴、比例、可访问性它都管了。
enum StatisticsChart {
  /// 一天的输入量。
  struct Day: Identifiable {
    let date: Date
    let count: Int
    var id: Date { date }
  }

  /// 一个分类。
  struct Slice: Identifiable {
    let id: String
    let title: String
    let count: Int
    let color: Color
    let symbol: String
  }
}

/// 每日趋势:折线加渐变面积。
struct StatisticsTrendChart: View {
  let days: [StatisticsChart.Day]
  let selected: Date?
  let accent: Color
  /// 进场时从左往右画出来。
  let progress: Double

  var body: some View {
    Chart(days) { day in
      AreaMark(x: .value("日期", day.date), y: .value("字符", day.count))
        .interpolationMethod(.catmullRom)
        .foregroundStyle(.linearGradient(colors: [accent.opacity(0.35), accent.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
      LineMark(x: .value("日期", day.date), y: .value("字符", day.count))
        .interpolationMethod(.catmullRom)
        .foregroundStyle(accent)
        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
      if let selected, Calendar.current.isDate(day.date, inSameDayAs: selected) {
        PointMark(x: .value("日期", day.date), y: .value("字符", day.count))
          .foregroundStyle(.orange)
          .symbolSize(90)
      }
    }
    .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { value in
      AxisGridLine()
      AxisValueLabel(format: .dateTime.month().day())
    } }
    .chartYAxis { AxisMarks(position: .trailing) }
    // 折线从左往右画出来:一整条直接出现,看不出它是按时间排的。
    .mask(alignment: .leading) {
      GeometryReader { geometry in
        Rectangle().frame(width: geometry.size.width * progress)
      }
    }
    .frame(height: 170)
    .accessibilityIdentifier("statisticsTrendChart")
  }
}

/// 日历热力图:一列一周,颜色深浅是当天的量。点一格看那一天。
struct StatisticsHeatmap: View {
  let days: [StatisticsChart.Day]
  let selected: Date?
  let accent: Color
  let onSelect: (Date) -> Void

  private var maximum: Int { max(1, days.map(\.count).max() ?? 1) }
  private var weeks: [[StatisticsChart.Day]] {
    stride(from: 0, to: days.count, by: 7).map {
      Array(days[$0..<min($0 + 7, days.count)])
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top, spacing: 4) {
        ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
          VStack(spacing: 4) {
            ForEach(week) { day in
              let level = Double(day.count) / Double(maximum)
              Button { onSelect(day.date) } label: {
                RoundedRectangle(cornerRadius: 3)
                  .fill(day.count == 0 ? Color.secondary.opacity(0.12) : accent.opacity(0.25 + 0.75 * level))
                  .frame(height: 16)
                  .overlay(
                    RoundedRectangle(cornerRadius: 3)
                      .strokeBorder(Color.orange, lineWidth: isSelected(day.date) ? 2 : 0))
              }
              .buttonStyle(.plain)
              .accessibilityLabel(day.date.formatted(.dateTime.month().day()))
              .accessibilityValue("\(day.count) 字符")
              .accessibilityIdentifier("statisticsDay_\(TypingStatistics.dayKey(day.date))")
            }
          }
        }
      }
      HStack(spacing: 5) {
        Text("少").font(.caption2).foregroundStyle(.secondary)
        ForEach([0.15, 0.4, 0.65, 1.0], id: \.self) { level in
          RoundedRectangle(cornerRadius: 2).fill(accent.opacity(0.25 + 0.75 * level))
            .frame(width: 12, height: 12)
        }
        Text("多").font(.caption2).foregroundStyle(.secondary)
      }
    }
    .accessibilityIdentifier("statisticsHeatmap")
  }

  private func isSelected(_ date: Date) -> Bool {
    guard let selected else { return false }
    return Calendar.current.isDate(date, inSameDayAs: selected)
  }
}

/// 饼图:看一类占了整块的多少。
struct StatisticsPieChart: View {
  let slices: [StatisticsChart.Slice]
  let progress: Double

  var body: some View {
    Chart(slices.filter { $0.count > 0 }) { slice in
      SectorMark(angle: .value(slice.title, Double(slice.count) * progress), angularInset: 1.5)
        .cornerRadius(3)
        .foregroundStyle(slice.color)
    }
    .frame(height: 190)
    .accessibilityIdentifier("statisticsPie")
  }
}

/// 环形图:中间留出总数,一眼看到「一共多少、谁占大头」。
struct StatisticsDonutChart: View {
  let slices: [StatisticsChart.Slice]
  let total: Int
  let progress: Double

  var body: some View {
    Chart(slices.filter { $0.count > 0 }) { slice in
      SectorMark(angle: .value(slice.title, Double(slice.count) * progress),
                 innerRadius: .ratio(0.62), angularInset: 1.5)
        .cornerRadius(3)
        .foregroundStyle(slice.color)
    }
    .chartBackground { _ in
      VStack(spacing: 2) {
        Text("\(total)").font(.system(size: 26, weight: .semibold, design: .rounded))
        Text("字符").font(.caption2).foregroundStyle(.secondary)
      }
    }
    .frame(height: 190)
    .accessibilityIdentifier("statisticsDonut")
  }
}

/// 横向排行:方案有十几种,平时只有两三种非零。按量排下来比切成十几瓣的饼看得清。
struct StatisticsRankChart: View {
  let slices: [StatisticsChart.Slice]
  let progress: Double

  private var ranked: [StatisticsChart.Slice] {
    slices.filter { $0.count > 0 }.sorted { $0.count > $1.count }
  }

  var body: some View {
    if ranked.isEmpty {
      Text("暂无输入记录").font(.subheadline).foregroundStyle(.secondary)
    } else {
      Chart(ranked) { slice in
        BarMark(x: .value("字符", Double(slice.count) * progress),
                y: .value("方案", slice.title))
          .cornerRadius(5)
          .foregroundStyle(slice.color)
          .annotation(position: .trailing) {
            Text("\(slice.count)").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
          }
      }
      .chartXAxis(.hidden)
      .frame(height: CGFloat(ranked.count) * 30 + 20)
      .accessibilityIdentifier("statisticsRank")
    }
  }
}
