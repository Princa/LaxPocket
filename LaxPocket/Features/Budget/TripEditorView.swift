import SwiftUI
import LaxPocketCore

/// Adds a tournament trip, or edits one: the event, where and when, how the family gets there, the hotel, and a budget.
struct TripEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The trip being edited; nil for a new one.
    let trip: Trip?
    @State private var name: String
    @State private var eventID: UUID?
    @State private var programID: String?
    @State private var destination: String
    @State private var country: TripCountry
    @State private var departureDate: Date
    @State private var returnDate: Date
    @State private var season: Int
    @State private var budgetText: String
    @State private var travelMode: TravelMode
    @State private var travelDetails: String
    @State private var hotelName: String
    @State private var hotelAddress: String
    @State private var hotelConfirmation: String
    @State private var hotelHasOwnDates: Bool
    @State private var hotelCheckIn: Date
    @State private var hotelCheckOut: Date
    @State private var note: String
    @State private var confirmDelete = false

    /// The team of the event a new trip started from, to pick its program.
    private let startingTeam: String?

    /// A new trip can start in a season, or from an event (its name, dates and place).
    init(trip: Trip? = nil, season: Int? = nil, event: SeasonEvent? = nil) {
        self.trip = trip
        startingTeam = trip == nil ? event?.team : nil
        // Editing shows the trip; a new trip from an event starts as a copy of it.
        let template = trip ?? event.map { Trip(event: $0) }
        let today = Calendar.laxWeek.startOfDay(for: Date())
        let departure = template?.departureDate ?? today
        let back = template?.returnDate ?? departure
        _name = State(initialValue: template?.name ?? "")
        _eventID = State(initialValue: template?.eventID)
        _programID = State(initialValue: template?.programID)
        _destination = State(initialValue: template?.destination ?? "")
        _country = State(initialValue: template?.country ?? .unitedStates)
        _departureDate = State(initialValue: departure)
        _returnDate = State(initialValue: back)
        _season = State(initialValue: template?.season ?? season ?? AthleteProfile.seasonStart(for: departure))
        _budgetText = State(initialValue: template.map { $0.budget > 0 ? AmountText.string($0.budget) : "" } ?? "")
        _travelMode = State(initialValue: template?.travelMode ?? .drive)
        _travelDetails = State(initialValue: template?.travelDetails ?? "")
        _hotelName = State(initialValue: template?.hotelName ?? "")
        _hotelAddress = State(initialValue: template?.hotelAddress ?? "")
        _hotelConfirmation = State(initialValue: template?.hotelConfirmation ?? "")
        _hotelHasOwnDates = State(initialValue: template?.hotelCheckIn != nil || template?.hotelCheckOut != nil)
        _hotelCheckIn = State(initialValue: template?.hotelCheckIn ?? departure)
        _hotelCheckOut = State(initialValue: template?.hotelCheckOut ?? back)
        _note = State(initialValue: template?.note ?? "")
    }

    private var isNew: Bool { trip == nil }
    /// Another trip already going to the picked event.
    private var otherTripToEvent: Trip? {
        eventID.flatMap(store.data.trip(forEvent:)).flatMap { $0.id == trip?.id ? nil : $0 }
    }
    /// Blank means no budget; anything typed has to be a number.
    private var budget: Double? {
        let text = budgetText.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return 0 }
        return AmountText.parse(text).flatMap { $0 >= 0 ? $0 : nil }
    }
    private var canSave: Bool {
        budget != nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Tournaments, showcases and camps without a trip yet, most recent first, plus the one already picked. An event
    /// has one trip.
    private var eventChoices: [SeasonEvent] {
        store.data.events.filter { event in
            if event.id == eventID { return true }
            guard event.kind != .game else { return false }
            return store.data.trip(forEvent: event.id).map { $0.id == trip?.id } ?? true
        }
        .sorted { $0.date > $1.date }
    }

    private var programChoices: [Program] {
        store.data.programs.filter { $0.runs(in: season) || $0.id == programID }
    }

    private var seasonChoices: [Int] {
        let current = store.profile.currentSeason(now: store.now)
        let seasons = Set(store.data.budgetSeasons(current: current)).union([season, AthleteProfile.seasonStart(for: departureDate), current - 1])
        return seasons.sorted(by: >)
    }

    /// The trip as typed, for the day counts in the footers.
    private var draft: Trip {
        Trip(id: trip?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines),
             destination: destination.trimmingCharacters(in: .whitespacesAndNewlines), country: country,
             departureDate: departureDate, returnDate: max(returnDate, departureDate), season: season,
             programID: programID.flatMap(store.program)?.id, eventID: eventID.flatMap { id in store.data.events.first(where: { $0.id == id })?.id },
             budget: budget ?? 0, travelMode: travelMode, travelDetails: travelDetails.trimmingCharacters(in: .whitespacesAndNewlines),
             hotelName: hotelName.trimmingCharacters(in: .whitespacesAndNewlines),
             hotelAddress: hotelAddress.trimmingCharacters(in: .whitespacesAndNewlines),
             hotelConfirmation: hotelConfirmation.trimmingCharacters(in: .whitespacesAndNewlines),
             hotelCheckIn: hotelHasOwnDates ? hotelCheckIn : nil, hotelCheckOut: hotelHasOwnDates ? max(hotelCheckOut, hotelCheckIn) : nil,
             note: note.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tournament, e.g. Fall Brawl", text: $name)
                    if !eventChoices.isEmpty {
                        Picker("Event", selection: $eventID) {
                            Text("None").tag(UUID?.none)
                            ForEach(eventChoices) { event in
                                Text("\(event.title) · \(Formatters.dayMonth(event.date))").tag(UUID?.some(event.id))
                            }
                        }
                    }
                    Picker("Team or program", selection: $programID) {
                        Text("None").tag(String?.none)
                        ForEach(programChoices) { program in
                            Text(program.name).tag(String?.some(program.id))
                        }
                    }
                } footer: {
                    if otherTripToEvent != nil {
                        Text("That event already has a trip. Its costs are best kept on that one.")
                    } else if eventID != nil {
                        Text("Linked to the event: the trip shows on its page, and moves when the event's dates change.")
                    } else if !eventChoices.isEmpty {
                        Text("Picking an event fills in its dates and place, and links the trip to it.")
                    }
                }

                Section {
                    TextField("City, e.g. Baltimore, MD", text: $destination)
                    Picker("Country", selection: $country) {
                        ForEach(TripCountry.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker("Leave", selection: $departureDate, displayedComponents: .date)
                    DatePicker("Back", selection: $returnDate, in: departureDate..., displayedComponents: .date)
                    Picker("Season", selection: $season) {
                        ForEach(seasonChoices, id: \.self) { Text(AthleteProfile.seasonLabel(start: $0)).tag($0) }
                    }
                } header: {
                    Text("Where and when")
                } footer: {
                    Text(daysFooter)
                }

                Section("Getting there") {
                    Picker("Travel", selection: $travelMode) {
                        ForEach(TravelMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    TextField("Flights, carpool, rental car, border crossing…", text: $travelDetails, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section {
                    TextField("Hotel", text: $hotelName)
                    TextField("Address", text: $hotelAddress, axis: .vertical).lineLimit(1...3)
                    TextField("Confirmation number", text: $hotelConfirmation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Toggle("Different dates from the trip", isOn: $hotelHasOwnDates)
                    if hotelHasOwnDates {
                        DatePicker("Check-in", selection: $hotelCheckIn, displayedComponents: .date)
                        DatePicker("Check-out", selection: $hotelCheckOut, in: hotelCheckIn..., displayedComponents: .date)
                    }
                } header: {
                    Text("Hotel")
                } footer: {
                    Text(hotelFooter)
                }

                Section {
                    TextField("Trip budget (CAD)", text: $budgetText).keyboardType(.decimalPad)
                } header: {
                    Text("Budget")
                } footer: {
                    Text("Optional. Add the fees, travel, hotel, food and other costs from the trip screen.")
                }

                Section("Notes") {
                    TextField("Packing list, who's driving, what's still owing…", text: $note, axis: .vertical)
                        .lineLimit(3...10)
                }

                if !isNew {
                    Section {
                        Button("Delete trip", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "Add trip" : "Edit trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.bold).disabled(!canSave)
                }
            }
            .onAppear {
                // A trip started from an event goes with the event's team, when that's a program.
                if isNew, programID == nil, let team = startingTeam, let match = store.data.programs.first(where: { $0.name == team }) {
                    programID = match.id
                }
            }
            .onChange(of: eventID) { _, new in
                guard let new, let event = store.data.events.first(where: { $0.id == new }) else { return }
                fill(from: event)
            }
            .onChange(of: departureDate) { old, new in
                if returnDate < new { returnDate = new }
                // The season follows the date until it's picked by hand.
                if season == AthleteProfile.seasonStart(for: old) { season = AthleteProfile.seasonStart(for: new) }
                if !hotelHasOwnDates { hotelCheckIn = new }
            }
            .onChange(of: returnDate) { _, new in
                if !hotelHasOwnDates { hotelCheckOut = new }
            }
            .onChange(of: hotelCheckIn) { _, new in
                if hotelCheckOut < new { hotelCheckOut = new }
            }
            .onChange(of: destination) { _, new in
                if let guess = TripCountry.guess(from: new) { country = guess }
            }
            .confirmationDialog(deleteTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
                let count = trip.map { store.data.expenses(forTrip: $0.id).count } ?? 0
                if count > 0 {
                    Button("Delete trip, keep \(count == 1 ? "its expense" : "its \(count) expenses")", role: .destructive) { delete(withExpenses: false) }
                    Button("Delete trip and \(count == 1 ? "its expense" : "its \(count) expenses")", role: .destructive) { delete(withExpenses: true) }
                } else {
                    Button("Delete", role: .destructive) { delete(withExpenses: false) }
                }
            }
        }
    }

    private var deleteTitle: String {
        let count = trip.map { store.data.expenses(forTrip: $0.id).count } ?? 0
        return count > 0 ? "Delete this trip? Kept expenses stay in the budget without the trip." : "Delete this trip?"
    }

    private var daysFooter: String {
        let trip = draft
        let days = trip.days(), nights = trip.nights()
        let length = days == 1 ? "A day trip" : "\(days) days, \(nights == 1 ? "1 night" : "\(nights) nights")"
        return trip.isInUS ? "\(length). Counts as \(days == 1 ? "1 day" : "\(days) days") in the US." : "\(length)."
    }

    private var hotelFooter: String {
        let trip = draft
        guard trip.hasHotel else { return "Add the hotel to keep its address and confirmation number with the trip." }
        let nights = trip.hotelNights()
        return nights == 1 ? "1 night." : "\(nights) nights."
    }

    /// An event's name, dates and place. A name already typed is kept.
    private func fill(from event: SeasonEvent) {
        let from = Trip(event: event, programID: programID)
        if name.trimmingCharacters(in: .whitespaces).isEmpty { name = from.name }
        departureDate = from.departureDate
        returnDate = from.returnDate
        if !from.destination.isEmpty {
            destination = from.destination
            country = from.country
        }
        if programID == nil, let match = store.data.programs.first(where: { $0.name == event.team }) { programID = match.id }
    }

    private func save() {
        guard canSave else { return }
        store.saveTrip(draft)
        dismiss()
    }

    private func delete(withExpenses: Bool) {
        guard let trip else { return }
        store.deleteTrip(trip.id, withExpenses: withExpenses)
        dismiss()
    }
}
