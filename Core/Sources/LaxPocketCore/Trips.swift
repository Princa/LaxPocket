import Foundation

/// Where a trip goes. Days in the United States are counted, for border crossings and travel insurance.
public enum TripCountry: String, Codable, CaseIterable, Identifiable, Sendable {
    case unitedStates = "US"
    case canada = "CA"
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .unitedStates: return "United States"
        case .canada: return "Canada"
        case .other: return "Elsewhere"
        }
    }

    private static let usStates: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
        "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD",
        "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY"
    ]
    private static let provinces: Set<String> = ["AB", "BC", "MB", "NB", "NL", "NS", "NT", "NU", "ON", "PE", "QC", "SK", "YT"]

    /// The country a place like "Baltimore, MD" or "Oakville, ON" is in, from the state or province at the end; nil when
    /// it doesn't say.
    public static func guess(from location: String) -> TripCountry? {
        let upper = location.uppercased()
        if upper.contains("USA") || upper.contains("UNITED STATES") { return .unitedStates }
        if upper.contains("CANADA") { return .canada }
        let words = upper.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        guard let last = words.last, last.count == 2, location.contains(",") else { return nil }
        if usStates.contains(last) { return .unitedStates }
        if provinces.contains(last) { return .canada }
        return nil
    }
}

public enum TravelMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case drive
    case fly
    case bus
    case train
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .drive: return "Drive"
        case .fly: return "Fly"
        case .bus: return "Bus"
        case .train: return "Train"
        case .other: return "Other"
        }
    }

    /// SF Symbol name.
    public var symbol: String {
        switch self {
        case .drive: return "car.fill"
        case .fly: return "airplane"
        case .bus: return "bus.fill"
        case .train: return "tram.fill"
        case .other: return "figure.walk"
        }
    }

    /// A safe value for one added by a newer version.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TravelMode(rawValue: raw) ?? .other
    }
}

/// A trip to a tournament, showcase or camp: where and when, how the family got there, the hotel, and what it cost
/// (the expenses that say they're for it).
public struct Trip: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// City, e.g. "Baltimore, MD".
    public var destination: String
    public var country: TripCountry
    /// The day the family leaves home.
    public var departureDate: Date
    /// The day they get back. The same day as `departureDate` for a day trip.
    public var returnDate: Date
    /// The season it counts toward, as the year it starts.
    public var season: Int
    /// The team or program it was with, if any.
    public var programID: String?
    /// The tournament, showcase or camp on the Events tab, if it's there.
    public var eventID: UUID?
    /// What's set aside for the trip; 0 if nothing.
    public var budget: Double
    public var travelMode: TravelMode
    /// Flights, carpool, rental car, border crossing…
    public var travelDetails: String
    public var hotelName: String
    public var hotelAddress: String
    public var hotelConfirmation: String
    /// Nil: the trip's dates.
    public var hotelCheckIn: Date?
    public var hotelCheckOut: Date?
    public var note: String

    public init(id: UUID = UUID(), name: String, destination: String = "", country: TripCountry = .unitedStates,
                departureDate: Date, returnDate: Date? = nil, season: Int? = nil, programID: String? = nil, eventID: UUID? = nil,
                budget: Double = 0, travelMode: TravelMode = .drive, travelDetails: String = "", hotelName: String = "",
                hotelAddress: String = "", hotelConfirmation: String = "", hotelCheckIn: Date? = nil, hotelCheckOut: Date? = nil,
                note: String = "") {
        self.id = id
        self.name = name
        self.destination = destination
        self.country = country
        self.departureDate = departureDate
        self.returnDate = returnDate ?? departureDate
        self.season = season ?? AthleteProfile.seasonStart(for: departureDate)
        self.programID = programID
        self.eventID = eventID
        self.budget = budget
        self.travelMode = travelMode
        self.travelDetails = travelDetails
        self.hotelName = hotelName
        self.hotelAddress = hotelAddress
        self.hotelConfirmation = hotelConfirmation
        self.hotelCheckIn = hotelCheckIn
        self.hotelCheckOut = hotelCheckOut
        self.note = note
    }

    /// A trip to an event on the Events tab: its name, dates and place, and the country when the place says.
    public init(event: SeasonEvent, programID: String? = nil) {
        self.init(name: event.title, destination: event.location, country: TripCountry.guess(from: event.location) ?? .unitedStates,
                  departureDate: event.date, returnDate: max(event.endDate ?? event.date, event.date), programID: programID,
                  eventID: event.id)
    }

    public var isInUS: Bool { country == .unitedStates }

    /// Calendar days away, counting the day they leave and the day they get back: Fri to Sun is 3 days.
    public func days(calendar: Calendar = .laxWeek) -> Int {
        Self.dayCount(from: departureDate, to: returnDate, calendar: calendar) + 1
    }

    /// Nights away: Fri to Sun is 2 nights.
    public func nights(calendar: Calendar = .laxWeek) -> Int {
        days(calendar: calendar) - 1
    }

    public var hasHotel: Bool {
        !hotelName.trimmingCharacters(in: .whitespaces).isEmpty || hotelCheckIn != nil
    }

    /// Hotel check-in and check-out, falling back to the trip's dates.
    public var hotelStay: (checkIn: Date, checkOut: Date) {
        (hotelCheckIn ?? departureDate, hotelCheckOut ?? returnDate)
    }

    /// Nights at the hotel; 0 with no hotel.
    public func hotelNights(calendar: Calendar = .laxWeek) -> Int {
        guard hasHotel else { return 0 }
        let stay = hotelStay
        return Self.dayCount(from: stay.checkIn, to: stay.checkOut, calendar: calendar)
    }

    /// The start of each calendar day of the trip. A trip typed with the return before the departure is one day.
    public func calendarDays(calendar: Calendar = .laxWeek) -> [Date] {
        let first = calendar.startOfDay(for: departureDate)
        // Capped at a year so a mistyped date can't make a huge list.
        let count = min(days(calendar: calendar), 366)
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    /// Whole calendar days from one date to another, never negative.
    static func dayCount(from start: Date, to end: Date, calendar: Calendar) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
        return max(days, 0)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, destination, country, departureDate, returnDate, season, programID, eventID, budget, travelMode, travelDetails,
             hotelName, hotelAddress, hotelConfirmation, hotelCheckIn, hotelCheckOut, note
    }

    /// Only the name and dates are required, so a trip saved by a newer version with fields this one doesn't know still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        destination = try c.decodeIfPresent(String.self, forKey: .destination) ?? ""
        country = (try? c.decodeIfPresent(TripCountry.self, forKey: .country)) ?? .other
        departureDate = try c.decode(Date.self, forKey: .departureDate)
        returnDate = try c.decodeIfPresent(Date.self, forKey: .returnDate) ?? departureDate
        season = try c.decodeIfPresent(Int.self, forKey: .season) ?? AthleteProfile.seasonStart(for: departureDate)
        programID = try c.decodeIfPresent(String.self, forKey: .programID)
        eventID = try c.decodeIfPresent(UUID.self, forKey: .eventID)
        budget = try c.decodeIfPresent(Double.self, forKey: .budget) ?? 0
        travelMode = try c.decodeIfPresent(TravelMode.self, forKey: .travelMode) ?? .drive
        travelDetails = try c.decodeIfPresent(String.self, forKey: .travelDetails) ?? ""
        hotelName = try c.decodeIfPresent(String.self, forKey: .hotelName) ?? ""
        hotelAddress = try c.decodeIfPresent(String.self, forKey: .hotelAddress) ?? ""
        hotelConfirmation = try c.decodeIfPresent(String.self, forKey: .hotelConfirmation) ?? ""
        hotelCheckIn = try c.decodeIfPresent(Date.self, forKey: .hotelCheckIn)
        hotelCheckOut = try c.decodeIfPresent(Date.self, forKey: .hotelCheckOut)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

/// What a trip cost, by category, and how long it was.
public struct TripSummary: Equatable, Sendable {
    public var trip: Trip
    /// Newest first.
    public var expenses: [Expense]
    public var spent: Double
    public var byCategory: [CategorySpend]
    public var days: Int
    public var nights: Int
    public var hotelNights: Int

    public var remaining: Double { trip.budget - spent }
    public var isOverBudget: Bool { trip.budget > 0 && spent > trip.budget }

    public func spent(on category: ExpenseCategory) -> Double {
        byCategory.first { $0.category == category }?.amount ?? 0
    }

    /// Hotel and lodging spending per hotel night, when there's both.
    public var lodgingPerNight: Double? {
        let lodging = spent(on: .lodging)
        return hotelNights > 0 && lodging > 0 ? lodging / Double(hotelNights) : nil
    }

    /// Food spending per day away, when there's some.
    public var foodPerDay: Double? {
        let food = spent(on: .food)
        return days > 0 && food > 0 ? food / Double(days) : nil
    }
}

/// Days in the US over a stretch of time: overall and per trip.
public struct USDaysSummary: Equatable, Sendable {
    /// Distinct calendar days, so overlapping trips count once.
    public var days: Int
    public var trips: Int
}

extension AppData {
    public func trip(id: UUID) -> Trip? {
        trips.first { $0.id == id }
    }

    /// A season's trips, soonest first.
    public func trips(in season: Int) -> [Trip] {
        trips.filter { $0.season == season }.sorted { ($0.departureDate, $0.name) < ($1.departureDate, $1.name) }
    }

    public func expenses(forTrip id: UUID) -> [Expense] {
        expenses.filter { $0.tripID == id }
    }
}

public enum TripMath {
    public static func summary(_ trip: Trip, in data: AppData, calendar: Calendar = .laxWeek) -> TripSummary {
        let expenses = data.expenses(forTrip: trip.id).sorted { $0.date > $1.date }
        let summary = BudgetMath.summary(expenses: expenses, budget: trip.budget)
        return TripSummary(trip: trip, expenses: expenses, spent: summary.spent, byCategory: summary.byCategory,
                           days: trip.days(calendar: calendar), nights: trip.nights(calendar: calendar),
                           hotelNights: trip.hotelNights(calendar: calendar))
    }

    /// Calendar days spent in the US on trips within an interval. A day two trips share counts once.
    public static func usDays(_ trips: [Trip], in interval: DateInterval, calendar: Calendar = .laxWeek) -> USDaysSummary {
        var days = Set<Date>()
        var count = 0
        for trip in trips where trip.isInUS {
            let inside = trip.calendarDays(calendar: calendar).filter { $0 >= interval.start && $0 < interval.end }
            if !inside.isEmpty { count += 1 }
            days.formUnion(inside)
        }
        return USDaysSummary(days: days.count, trips: count)
    }

    /// January 1 to December 31.
    public static func interval(year: Int, calendar: Calendar = .laxWeek) -> DateInterval {
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date.distantPast
        let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? Date.distantFuture
        return DateInterval(start: start, end: end)
    }

    /// August 1 to July 31, the same as seasons everywhere else.
    public static func interval(season: Int, calendar: Calendar = .laxWeek) -> DateInterval {
        let start = calendar.date(from: DateComponents(year: season, month: 8, day: 1)) ?? Date.distantPast
        let end = calendar.date(from: DateComponents(year: season + 1, month: 8, day: 1)) ?? Date.distantFuture
        return DateInterval(start: start, end: end)
    }
}
