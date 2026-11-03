import SwiftUI

/// Listening analytics from the local history: time per day and hour, top artists and tracks,
/// which service it came from, and how loud (Mac output volume while playing on the headphones).
struct ListeningPage: View {
    @ObservedObject private var log = ListeningLog.shared
    @State private var days = 7

    var body: some View {
        let stats = ListeningStats(sessions: log.sessions, volume: log.volume, days: days)
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "Listening", subtitle: "What you played and how loud, over the last \(days) days")
                .overlay(alignment: .topTrailing) { RangePicker(days: $days).padding(.top, 10) }

            if stats.totalSeconds < 1 {
                Card(title: "Nothing recorded yet") {
                    Text("While Connect Head is running it notes what plays in Music, Spotify and YouTube, and how loud your Mac sends it to the headphones. Play something and it will show up here.")
                        .font(.headline(14, weight: .regular)).italic()
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(alignment: .top, spacing: 22) {
                    StatPanel(label: "Listening time", value: Duration.text(stats.totalSeconds),
                              detail: "\(Duration.text(stats.totalSeconds / Double(days))) a day on average")
                    StatPanel(label: "Most played", value: stats.topArtists.first?.name ?? "—",
                              detail: stats.topArtists.first.map { Duration.text($0.seconds) } ?? "")
                    StatPanel(label: "Average volume", value: stats.averageVolume.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                              detail: stats.averageVolume == nil ? "Recorded when the Mac plays to your headphones"
                                  : "\(Duration.text(stats.loudSeconds)) above 75%")
                }

                Card(title: "Listening time by day") {
                    InkBarChart(values: stats.perDay.map(\.seconds), labels: stats.perDay.map(\.label),
                                readout: { i, v in "\(stats.perDay[i].longLabel): \(Duration.text(v))" })
                        .frame(height: 140)
                }

                Card(title: "When you listen") {
                    InkBarChart(values: stats.perHour, labels: (0..<24).map { $0 % 6 == 0 ? Self.hourLabel($0) : "" },
                                readout: { i, v in "\(Self.hourLabel(i))–\(Self.hourLabel((i + 1) % 24)): \(Duration.text(v))" })
                        .frame(height: 100)
                }

                HStack(alignment: .top, spacing: 22) {
                    Card(title: "Top artists") { RankedList(rows: Array(stats.topArtists.prefix(5))) }
                    Card(title: "Top tracks") { RankedList(rows: Array(stats.topTracks.prefix(5))) }
                }

                Card(title: "Where it played") { RankedList(rows: stats.services, showsShare: true) }

                Card(title: "Volume while listening") {
                    if stats.perDayVolume.allSatisfy({ $0 == nil }) {
                        Text("Volume is recorded when your Mac plays through the headphones. Nothing yet in this period.")
                            .font(.headline(13, weight: .regular)).italic().foregroundStyle(.secondary)
                    } else {
                        InkLineChart(values: stats.perDayVolume, labels: stats.perDay.map(\.label), reference: 0.75,
                                     referenceLabel: "75%",
                                     readout: { i, v in "\(stats.perDay[i].longLabel): \(Int((v * 100).rounded()))% average" })
                            .frame(height: 130)
                        Text("A common guideline for long sessions is the 60/60 rule: under 60% volume, for about 60 minutes at a time.")
                            .font(.headline(12, weight: .regular)).italic().foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private static func hourLabel(_ h: Int) -> String {
        h == 0 ? "12a" : h < 12 ? "\(h)a" : h == 12 ? "12p" : "\(h - 12)p"
    }
}

// MARK: - Stats

struct ListeningStats {
    struct Day { let label: String; let longLabel: String; let seconds: Double }
    struct Row: Identifiable { var id: String { name }; let name: String; let detail: String; let seconds: Double }

    let totalSeconds: Double
    let perDay: [Day]
    let perHour: [Double]
    let topArtists: [Row]
    let topTracks: [Row]
    let services: [Row]
    let perDayVolume: [Double?]
    let averageVolume: Double?
    let loudSeconds: Double

    init(sessions: [ListeningLog.Session], volume: [ListeningLog.VolumeMinute], days: Int, now: Date = .now) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .day, value: -(days - 1), to: today)!
        let recent = sessions.filter { $0.end > start }
        let loud = volume.filter { $0.minute >= start }

        totalSeconds = recent.reduce(0) { $0 + $1.seconds }

        let short = DateFormatter(), long = DateFormatter()
        short.setLocalizedDateFormatFromTemplate(days <= 7 ? "EEEEE" : "d")
        long.setLocalizedDateFormatFromTemplate("EEEE d MMM")
        var byDay = [Date: Double](), byDayVolume = [Date: (Double, Double)]()
        var hours = [Double](repeating: 0, count: 24)
        for s in recent {
            byDay[cal.startOfDay(for: s.start), default: 0] += s.seconds
            hours[cal.component(.hour, from: s.start)] += s.seconds
        }
        for v in loud {
            let d = cal.startOfDay(for: v.minute)
            let prev = byDayVolume[d] ?? (0, 0)
            byDayVolume[d] = (prev.0 + v.level * v.seconds, prev.1 + v.seconds)
        }
        let dayList = (0..<days).map { cal.date(byAdding: .day, value: $0, to: start)! }
        perDay = dayList.map { Day(label: short.string(from: $0), longLabel: long.string(from: $0), seconds: byDay[$0] ?? 0) }
        perDayVolume = dayList.map { d in byDayVolume[d].flatMap { $0.1 > 0 ? $0.0 / $0.1 : nil } }
        perHour = hours

        func ranked(_ key: (ListeningLog.Session) -> String, detail: (String, [ListeningLog.Session]) -> String) -> [Row] {
            Dictionary(grouping: recent, by: key)
                .map { name, group in Row(name: name, detail: detail(name, group), seconds: group.reduce(0) { $0 + $1.seconds }) }
                .sorted { $0.seconds > $1.seconds }
        }
        topArtists = ranked({ $0.artist.isEmpty ? $0.service : $0.artist }) { _, group in
            let tracks = Set(group.map(\.title)).count
            return tracks == 1 ? "1 track" : "\(tracks) tracks"
        }
        topTracks = ranked({ $0.title }) { _, group in group.first?.artist.isEmpty == false ? group[0].artist : group[0].service }
        services = ranked({ $0.service }) { _, _ in "" }

        let volumeSeconds = loud.reduce(0) { $0 + $1.seconds }
        averageVolume = volumeSeconds > 0 ? loud.reduce(0) { $0 + $1.level * $1.seconds } / volumeSeconds : nil
        loudSeconds = loud.filter { $0.level > 0.75 }.reduce(0) { $0 + $1.seconds }
    }
}

enum Duration {
    static func text(_ seconds: Double) -> String {
        let m = Int((seconds / 60).rounded())
        if m < 1 { return seconds > 0 ? "<1m" : "0m" }
        return m < 60 ? "\(m)m" : m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }
}

// MARK: - Pieces

private struct RangePicker: View {
    @Binding var days: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach([7, 30], id: \.self) { d in
                Button { days = d } label: {
                    Text("\(d) days")
                        .font(.system(size: 10, weight: .semibold)).tracking(1.2).textCase(.uppercase)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .foregroundStyle(days == d ? Theme.sheet : Theme.ink)
                        .background(days == d ? Theme.ink : .clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.ink, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .fixedSize()
    }
}

private struct StatPanel: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10, weight: .semibold)).tracking(1.6).textCase(.uppercase)
            Text(value).font(.headline(30, weight: .regular)).lineLimit(1).minimumScaleFactor(0.6)
            Text(detail).font(.headline(12, weight: .regular)).italic().foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .printPanel()
    }
}

/// Name, detail and duration per row, with a hairline bar scaled to the top row.
private struct RankedList: View {
    let rows: [ListeningStats.Row]
    var showsShare = false

    var body: some View {
        let top = rows.first?.seconds ?? 1
        let total = rows.reduce(0) { $0 + $1.seconds }
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.name).font(.headline(14, weight: .medium)).lineLimit(1)
                        if !row.detail.isEmpty {
                            Text(row.detail).font(.headline(12, weight: .regular)).italic().foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(showsShare ? "\(Int((row.seconds / max(total, 1) * 100).rounded()))%  ·  \(Duration.text(row.seconds))"
                                        : Duration.text(row.seconds))
                            .font(.headline(12.5, weight: .regular)).monospacedDigit()
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Theme.ink.opacity(0.12)).frame(height: 1)
                            Rectangle().fill(Theme.ink).frame(width: geo.size.width * row.seconds / max(top, 1), height: 3)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(height: 4)
                }
            }
        }
    }
}

/// Single-series bar chart in ink, with a value readout for the hovered bar.
private struct InkBarChart: View {
    let values: [Double]
    let labels: [String]
    let readout: (Int, Double) -> String
    @State private var hovered: Int?

    var body: some View {
        let top = max(values.max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 6) {
            Text(hovered.map { readout($0, values[$0]) } ?? " ")
                .font(.headline(12, weight: .regular)).italic().foregroundStyle(.secondary)
            GeometryReader { geo in
                let gap: CGFloat = values.count > 12 ? 3 : 8
                let barWidth = (geo.size.width - gap * CGFloat(values.count - 1)) / CGFloat(values.count)
                ZStack(alignment: .bottomLeading) {
                    Rectangle().fill(Theme.ink.opacity(0.5)).frame(height: 0.75)   // baseline
                    HStack(alignment: .bottom, spacing: gap) {
                        ForEach(values.indices, id: \.self) { i in
                            let h = values[i] > 0 ? max(geo.size.height * values[i] / top, 2) : 0
                            UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                                .fill(Theme.ink.opacity(hovered == nil || hovered == i ? 1 : 0.35))
                                .frame(width: min(barWidth, 34), height: h)
                                .frame(width: barWidth, height: geo.size.height, alignment: .bottom)
                                .contentShape(Rectangle())
                                .onHover { inside in hovered = inside ? i : (hovered == i ? nil : hovered) }
                        }
                    }
                }
            }
            HStack(spacing: 0) {
                ForEach(labels.indices, id: \.self) { i in
                    Text(labels[i]).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .fixedSize()
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// Single-series line in ink over 0…1, with a dashed reference line and a hover readout.
/// Days without data leave gaps.
private struct InkLineChart: View {
    let values: [Double?]
    let labels: [String]
    let reference: Double
    let referenceLabel: String
    let readout: (Int, Double) -> String
    @State private var hovered: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(hovered.flatMap { i in values[i].map { readout(i, $0) } } ?? " ")
                .font(.headline(12, weight: .regular)).italic().foregroundStyle(.secondary)
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let step = values.count > 1 ? w / CGFloat(values.count - 1) : 0
                let point = { (i: Int, v: Double) in CGPoint(x: CGFloat(i) * step, y: h - CGFloat(v) * h) }
                ZStack(alignment: .topLeading) {
                    Path { p in p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: w, y: h)) }
                        .stroke(Theme.ink.opacity(0.5), lineWidth: 0.75)
                    Path { p in
                        let y = h - CGFloat(reference) * h
                        p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(Theme.accent.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    Text(referenceLabel).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                        .position(x: w - 12, y: h - CGFloat(reference) * h - 8)
                    Path { p in
                        var drawing = false
                        for (i, v) in values.enumerated() {
                            guard let v else { drawing = false; continue }
                            drawing ? p.addLine(to: point(i, v)) : p.move(to: point(i, v))
                            drawing = true
                        }
                    }
                    .stroke(Theme.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    ForEach(values.indices, id: \.self) { i in
                        if let v = values[i] {
                            Circle().fill(Theme.sheet)
                                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2))
                                .frame(width: hovered == i ? 11 : 8, height: hovered == i ? 11 : 8)
                                .position(point(i, v))
                        }
                    }
                    if let i = hovered {
                        Path { p in p.move(to: CGPoint(x: CGFloat(i) * step, y: 0)); p.addLine(to: CGPoint(x: CGFloat(i) * step, y: h)) }
                            .stroke(Theme.ink.opacity(0.3), lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active(let p) = phase, step > 0 {
                        hovered = min(max(Int((p.x / step).rounded()), 0), values.count - 1)
                    } else {
                        hovered = nil
                    }
                }
            }
            HStack(spacing: 0) {
                ForEach(labels.indices, id: \.self) { i in
                    Text(labels[i]).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
                    if i < labels.count - 1 { Spacer(minLength: 0) }
                }
            }
        }
    }
}
