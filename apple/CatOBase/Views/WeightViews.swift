import Charts
import SwiftData
import SwiftUI

enum WeightRange: String, CaseIterable, Identifiable {
    case sixMonths = "6M"
    case year = "1Y"
    case all = "All"

    var id: String { rawValue }

    var startDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .sixMonths: return calendar.date(byAdding: .month, value: -6, to: .now)
        case .year: return calendar.date(byAdding: .year, value: -1, to: .now)
        case .all: return nil
        }
    }
}

// MARK: - Section on the cat page

struct WeightSection: View {
    let cat: Cat
    let onLog: () -> Void

    @AppStorage(PrefKey.weightUnit) private var unit: WeightUnit = .kg
    @State private var range: WeightRange = .year

    var body: some View {
        Section("Weight") {
            if let trend = cat.weightTrend {
                let entries = cat.weightsNewestFirst
                summary(trend)
                if trend.isWarning, let percent = trend.percentChange, let since = trend.referenceDate {
                    CalloutRow(
                        title: "Weight loss",
                        text: "Down \(Fmt.percent(abs(percent))) since \(Fmt.date(since)). Worth mentioning to the vet.",
                        systemImage: "exclamationmark.triangle.fill",
                        tint: .red
                    )
                }
                if entries.count >= 2 {
                    Picker("Range", selection: $range) {
                        ForEach(WeightRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help("Chart time range")
                    WeightChart(entries: chartEntries(in: range, from: entries), unit: unit)
                        .frame(height: 190)
                        .padding(.vertical, 4)
                } else {
                    Text("Log another weigh-in to see the chart.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                NavigationLink {
                    WeightHistoryView(cat: cat)
                } label: {
                    LabeledContent("History", value: entries.count == 1 ? "1 weigh-in" : "\(entries.count) weigh-ins")
                }
            } else {
                Text("No weigh-ins yet.")
                    .foregroundStyle(.secondary)
            }
            Button(action: onLog) {
                Label("Log Weight", systemImage: "plus")
            }
            .help("Record a weigh-in")
        }
    }

    private func summary(_ trend: WeightTrend) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(unit.format(kilograms: trend.latest.kg))
                    .font(.title2.bold())
                Text("Weighed \(Fmt.date(trend.latest.date))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let change = trend.changeSincePrevious {
                    Text("\(unit.formatChange(kilograms: change)) since last")
                        .foregroundStyle(change < 0 ? Color.orange : Color.secondary)
                }
                if let percent = trend.percentChange, let since = trend.referenceDate {
                    Text("\(Fmt.signedPercent(percent)) since \(Fmt.date(since))")
                        .foregroundStyle(trend.isWarning ? Color.red : Color.secondary)
                }
            }
            .font(.caption)
        }
    }

    /// Entries in the chosen range; falls back to everything if fewer than two are in it.
    private func chartEntries(in range: WeightRange, from all: [WeightEntry]) -> [WeightEntry] {
        guard let start = range.startDate else { return all }
        let inRange = all.filter { $0.date >= start }
        return inRange.count >= 2 ? inRange : all
    }
}

// MARK: - Chart

struct WeightPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

struct WeightChart: View {
    let entries: [WeightEntry]
    let unit: WeightUnit
    @State private var selectedDate: Date?

    private var points: [WeightPoint] {
        entries
            .sorted { $0.date < $1.date }
            .map { WeightPoint(date: $0.date, value: unit.fromKilograms($0.kg)) }
    }

    var body: some View {
        let chartPoints = self.points
        let domain = yDomain(for: chartPoints)
        Chart {
            ForEach(chartPoints) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Base", domain.lowerBound),
                    yEnd: .value("Weight", point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom)
                )
                LineMark(x: .value("Date", point.date), y: .value("Weight", point.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                PointMark(x: .value("Date", point.date), y: .value("Weight", point.value))
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(30)
            }
            if let selected = nearest(to: selectedDate, in: chartPoints) {
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 1) {
                            Text(selected.value.formatted(.number.precision(.fractionLength(0...2))) + " " + unit.rawValue)
                                .font(.caption.bold())
                            Text(Fmt.date(selected.date))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
            }
        }
        .chartYScale(domain: domain)
        .chartXSelection(value: $selectedDate)
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .accessibilityLabel("Weight chart")
        .help("Hover or drag across the chart to see each weigh-in")
    }

    private func yDomain(for points: [WeightPoint]) -> ClosedRange<Double> {
        let values = points.map(\.value)
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let padding = max((high - low) * 0.2, unit == .kg ? 0.2 : 0.5)
        return (low - padding)...(high + padding)
    }

    private func nearest(to date: Date?, in points: [WeightPoint]) -> WeightPoint? {
        guard let date else { return nil }
        return points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

// MARK: - Log / edit a weigh-in

struct WeightEntryEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let cat: Cat
    let entry: WeightEntry?
    private let unit: WeightUnit

    @State private var date: Date
    @State private var text: String
    @FocusState private var fieldFocused: Bool

    init(cat: Cat, entry: WeightEntry?) {
        self.cat = cat
        self.entry = entry
        let stored = UserDefaults.standard.string(forKey: PrefKey.weightUnit) ?? ""
        let unit = WeightUnit(rawValue: stored) ?? .kg
        self.unit = unit
        _date = State(initialValue: entry?.date ?? Date())
        if let entry {
            let value = unit.fromKilograms(entry.kg)
            _text = State(initialValue: value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)))
        } else {
            _text = State(initialValue: "")
        }
    }

    private var parsed: Double? { WeightUnit.parse(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Weight", text: $text)
                            .focused($fieldFocused)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .font(.title2)
                        Text(unit.rawValue)
                            .foregroundStyle(.secondary)
                    }
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                } footer: {
                    if entry == nil, let last = cat.weightTrend?.latest {
                        Text("Last weigh-in: \(unit.format(kilograms: last.kg)) on \(Fmt.date(last.date)).")
                    }
                }

                if let entry {
                    Section {
                        Button("Delete Weigh-in", role: .destructive) {
                            context.delete(entry)
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(entry == nil ? "Log Weight" : "Edit Weigh-in")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(parsed == nil)
                }
            }
            .onAppear { fieldFocused = true }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 260)
        #endif
    }

    private func save() {
        guard let value = parsed else { return }
        let target: WeightEntry
        if let entry {
            target = entry
        } else {
            target = WeightEntry()
            context.insert(target)
            target.cat = cat
        }
        target.date = date
        target.kg = unit.toKilograms(value)
        try? context.save()
        dismiss()
    }
}

// MARK: - History

struct WeightHistoryView: View {
    @Environment(\.modelContext) private var context
    let cat: Cat

    @AppStorage(PrefKey.weightUnit) private var unit: WeightUnit = .kg
    @State private var editing: WeightEntry?
    @State private var adding = false

    var body: some View {
        let entries = cat.weightsNewestFirst
        List {
            ForEach(Array(entries.enumerated()), id: \.element.persistentModelID) { index, entry in
                HStack {
                    Text(Fmt.date(entry.date))
                    Spacer()
                    if index + 1 < entries.count {
                        let change = entry.kg - entries[index + 1].kg
                        Text(unit.formatChange(kilograms: change))
                            .font(.caption)
                            .foregroundStyle(change < 0 ? Color.orange : Color.secondary)
                    }
                    Text(unit.format(kilograms: entry.kg))
                        .monospacedDigit()
                        .frame(minWidth: 70, alignment: .trailing)
                }
                .contentShape(Rectangle())
                .onTapGesture { editing = entry }
                .help("Click to edit. Right-click to delete.")
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        context.delete(entry)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button("Edit") { editing = entry }
                    Button("Delete", role: .destructive) { context.delete(entry) }
                }
            }
        }
        .comfortableListOnMac()
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView("No Weigh-ins", systemImage: "scalemass")
            }
        }
        .navigationTitle("Weight History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    adding = true
                } label: {
                    Label("Log Weight", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editing) { entry in
            WeightEntryEditView(cat: cat, entry: entry)
        }
        .sheet(isPresented: $adding) {
            WeightEntryEditView(cat: cat, entry: nil)
        }
    }
}

#Preview {
    NavigationStack {
        List {
            WeightSection(cat: PreviewData.murka) {}
        }
    }
    .modelContainer(PreviewData.container)
}
