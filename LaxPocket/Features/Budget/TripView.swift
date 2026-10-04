import SwiftUI
import LaxPocketCore

/// One tournament trip: what it cost by category (fees, travel, hotel, food, other), days away and in the US, the hotel,
/// how the family got there, and every expense.
struct TripView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID
    @State private var editing: ExpenseEditTarget?
    /// The trip as it was when Edit was tapped, so the sheet keeps it while it closes after a delete.
    @State private var editingTrip: Trip?

    /// An athlete's own login sees the budget but doesn't change it.
    private var canEdit: Bool { store.data.canWrite(.budget) }

    var body: some View {
        Group {
            if let trip = store.trip(tripID) {
                content(TripMath.summary(trip, in: store.data))
            } else {
                Text("This trip was deleted.").foregroundStyle(AppTheme.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let trip = store.trip(tripID), canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { editingTrip = trip }
                }
            }
        }
        .sheet(item: $editing) { target in
            ExpenseEditorView(expense: target.expense, programID: target.programID, season: target.season, tripID: target.tripID,
                              category: target.category)
        }
        .sheet(item: $editingTrip) { trip in TripEditorView(trip: trip) }
        .onChange(of: store.trip(tripID) == nil) { _, deleted in
            if deleted { dismiss() }
        }
    }

    private func content(_ summary: TripSummary) -> some View {
        let trip = summary.trip
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    ScreenTitle(text: trip.name.isEmpty ? "Trip" : trip.name)
                    Text(subtitle(trip)).font(.system(size: 14)).foregroundStyle(AppTheme.muted)
                }

                summaryCard(summary)

                SectionHeader(title: "Costs").padding(.top, 8)
                Card(padding: 0) {
                    let categories = costCategories(summary)
                    ForEach(Array(categories.enumerated()), id: \.element) { index, category in
                        costRow(category, summary: summary)
                        if index < categories.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                    }
                }

                if trip.hasHotel {
                    SectionHeader(title: "Hotel").padding(.top, 8)
                    hotelCard(trip, nights: summary.hotelNights)
                }

                if !trip.travelDetails.isEmpty || trip.travelMode != .drive {
                    SectionHeader(title: "Getting there").padding(.top, 8)
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(trip.travelMode.title, systemImage: trip.travelMode.symbol)
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                            if !trip.travelDetails.isEmpty {
                                Text(trip.travelDetails).font(.system(size: 14)).foregroundStyle(AppTheme.ink2).textSelection(.enabled)
                            }
                        }
                    }
                }

                if let event = trip.eventID.flatMap({ id in store.data.events.first(where: { $0.id == id }) }) {
                    SectionHeader(title: "Event").padding(.top, 8)
                    Card(padding: 0) {
                        NavigationLink { GameDetailView(eventID: event.id) } label: {
                            HStack(spacing: 12) {
                                DateBadge(top: Formatters.monthShort(event.date), bottom: Formatters.dayNumber(event.date))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                                    Text([event.kind.title, event.location].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.chevron)
                            }
                            .padding(14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                SectionHeader(title: "Expenses").padding(.top, 8)
                if summary.expenses.isEmpty {
                    Card {
                        Text(canEdit ? "Nothing recorded yet. Tap + next to a cost above to add the entry fee, gas, flights, hotel or meals."
                                     : "Nothing recorded yet.")
                            .font(.system(size: 14)).foregroundStyle(AppTheme.ink2)
                    }
                } else {
                    Card(padding: 0) {
                        ForEach(Array(summary.expenses.enumerated()), id: \.element.id) { index, expense in
                            Button { editing = ExpenseEditTarget(expense: expense, season: expense.season) } label: {
                                ExpenseListRow(expense: expense, showsTrip: false)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 14)
                            .allowsHitTesting(canEdit)
                            .contextMenu {
                                if canEdit {
                                    Button { editing = ExpenseEditTarget(expense: expense, season: expense.season) } label: { Label("Edit", systemImage: "pencil") }
                                    Button(role: .destructive) { store.deleteExpenses([expense.id]) } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                            if index < summary.expenses.count - 1 { Divider().overlay(AppTheme.line).padding(.leading, 14) }
                        }
                    }
                }

                if canEdit {
                    Button { editing = newExpense(trip, category: nil) } label: {
                        Label("Add expense", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryButtonStyle(color: theme.primary))
                    .padding(.top, 8)
                }

                if !trip.note.isEmpty {
                    SectionHeader(title: "Notes").padding(.top, 8)
                    Card {
                        Text(trip.note).font(.system(size: 14)).foregroundStyle(AppTheme.ink2).textSelection(.enabled)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Pieces

    private func subtitle(_ trip: Trip) -> String {
        var parts: [String] = []
        if !trip.destination.isEmpty { parts.append(trip.destination) }
        parts.append(TripDates.range(trip))
        if let program = trip.programID.flatMap(store.program) { parts.append(program.name) }
        return parts.joined(separator: " · ")
    }

    private func summaryCard(_ summary: TripSummary) -> some View {
        let trip = summary.trip
        return Card(padding: 20, radius: 20) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trip cost").font(.system(size: 13)).foregroundStyle(AppTheme.caption)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(store.money(summary.spent)).font(.display(48)).foregroundStyle(theme.primary)
                        if trip.budget > 0 {
                            Text("of \(store.money(trip.budget))").font(.system(size: 14)).foregroundStyle(AppTheme.caption)
                        }
                    }
                }
                if trip.budget > 0 {
                    ProgressView(value: min(summary.spent / trip.budget, 1))
                        .tint(summary.isOverBudget ? theme.accentText : theme.primary)
                        .scaleEffect(x: 1, y: 2, anchor: .center)
                    Text(summary.isOverBudget ? "\(store.money(-summary.remaining)) over budget" : "\(store.money(summary.remaining)) left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(summary.isOverBudget ? theme.accentText : AppTheme.ink2)
                }
                HStack(spacing: 0) {
                    stat("\(summary.days)", summary.days == 1 ? "Day" : "Days")
                    stat("\(summary.nights)", summary.nights == 1 ? "Night" : "Nights")
                    stat(trip.isInUS ? "\(summary.days)" : "0", "Days in US")
                }
                if !trip.isInUS {
                    Text(trip.country == .canada ? "In Canada, so no days in the US." : "Outside the US and Canada.")
                        .font(.system(size: 12)).foregroundStyle(AppTheme.caption)
                }
            }
        }
    }

    private func stat(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.display(24)).foregroundStyle(AppTheme.ink)
            Text(caption).font(.system(size: 12)).foregroundStyle(AppTheme.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The usual trip costs, then any other category the trip's expenses use.
    private func costCategories(_ summary: TripSummary) -> [ExpenseCategory] {
        let extra = summary.byCategory.map(\.category).filter { !ExpenseCategory.tripCategories.contains($0) }
        return ExpenseCategory.tripCategories + extra
    }

    private func costRow(_ category: ExpenseCategory, summary: TripSummary) -> some View {
        let amount = summary.spent(on: category)
        let count = summary.expenses.filter { $0.category == category }.count
        return HStack(spacing: 12) {
            Image(systemName: category.tripSymbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.primary)
                .frame(width: 36, height: 36)
                .background(theme.primaryTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.tripTitle).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                Text(costCaption(category, count: count, summary: summary)).font(.system(size: 12)).foregroundStyle(AppTheme.caption)
            }
            Spacer()
            Text(amount > 0 ? store.money(amount) : "—")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(amount > 0 ? AppTheme.ink : AppTheme.caption)
            if canEdit {
                Button { editing = newExpense(summary.trip, category: category) } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 24)).foregroundStyle(theme.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(category.tripTitle.lowercased())")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .accessibilityElement(children: .contain)
    }

    private func costCaption(_ category: ExpenseCategory, count: Int, summary: TripSummary) -> String {
        if category == .lodging, let perNight = summary.lodgingPerNight {
            return "\(store.money(perNight)) a night · \(summary.hotelNights == 1 ? "1 night" : "\(summary.hotelNights) nights")"
        }
        if category == .food, let perDay = summary.foodPerDay {
            return "\(store.money(perDay)) a day"
        }
        if count == 0 { return category.tripHint }
        return count == 1 ? "1 expense" : "\(count) expenses"
    }

    private func hotelCard(_ trip: Trip, nights: Int) -> some View {
        let stay = trip.hotelStay
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(trip.hotelName.isEmpty ? "Hotel" : trip.hotelName).font(.system(size: 16, weight: .semibold)).foregroundStyle(AppTheme.ink)
                if !trip.hotelAddress.isEmpty {
                    if let url = mapsURL(trip.hotelAddress) {
                        Link(destination: url) {
                            Label(trip.hotelAddress, systemImage: "mappin.and.ellipse").font(.system(size: 14))
                        }
                    } else {
                        Text(trip.hotelAddress).font(.system(size: 14)).foregroundStyle(AppTheme.ink2)
                    }
                }
                if !trip.hotelConfirmation.isEmpty {
                    HStack(spacing: 6) {
                        Text("Confirmation").foregroundStyle(AppTheme.caption)
                        Text(trip.hotelConfirmation).fontWeight(.semibold).foregroundStyle(AppTheme.ink).textSelection(.enabled)
                    }
                    .font(.system(size: 14))
                }
                Text("Check-in \(Formatters.dayMonth(stay.checkIn)) · check-out \(Formatters.dayMonth(stay.checkOut)) · \(nights == 1 ? "1 night" : "\(nights) nights")")
                    .font(.system(size: 13)).foregroundStyle(AppTheme.caption)
            }
        }
    }

    private func mapsURL(_ address: String) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: address)]
        return components?.url
    }

    /// A new expense for this trip: its season and program, and the category tapped.
    private func newExpense(_ trip: Trip, category: ExpenseCategory?) -> ExpenseEditTarget {
        ExpenseEditTarget(programID: trip.programID.flatMap(store.program)?.id, season: trip.season, tripID: trip.id, category: category)
    }
}

/// "Oct 15 – 18" or "Oct 30 – Nov 2" for a trip; one date for a day trip.
enum TripDates {
    static func range(_ trip: Trip, calendar: Calendar = .laxWeek) -> String {
        let start = trip.departureDate, end = max(trip.returnDate, trip.departureDate)
        if calendar.isDate(start, inSameDayAs: end) { return Formatters.dayMonth(start) }
        if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            return "\(Formatters.dayMonth(start)) – \(Formatters.dayNumber(end))"
        }
        return "\(Formatters.dayMonth(start)) – \(Formatters.dayMonth(end))"
    }
}

extension ExpenseCategory {
    /// Shorter names for the trip screen.
    var tripTitle: String {
        switch self {
        case .tournamentFees: return "Tournament fee"
        case .travel: return "Travel"
        case .lodging: return "Hotel"
        case .food: return "Food"
        case .other: return "Other"
        default: return title
        }
    }

    /// What goes in a trip cost that has nothing yet.
    var tripHint: String {
        switch self {
        case .tournamentFees: return "Entry and registration"
        case .travel: return "Gas, flights, car rental, parking"
        case .lodging: return "Hotel, motel, rental"
        case .food: return "Meals, groceries, snacks"
        case .other: return "Tolls, souvenirs, anything else"
        default: return "Nothing yet"
        }
    }

    /// SF Symbol name.
    var tripSymbol: String {
        switch self {
        case .tournamentFees: return "trophy.fill"
        case .travel: return "car.fill"
        case .lodging: return "bed.double.fill"
        case .food: return "fork.knife"
        case .other: return "ellipsis.circle.fill"
        case .teamFees: return "person.3.fill"
        case .coaching: return "figure.run"
        case .fitness: return "dumbbell.fill"
        case .showcases: return "star.fill"
        case .equipment: return "bag.fill"
        case .facility: return "building.2.fill"
        }
    }
}
