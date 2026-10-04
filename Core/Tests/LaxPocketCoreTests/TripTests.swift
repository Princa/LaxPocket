import XCTest
@testable import LaxPocketCore

final class TripTests: XCTestCase {
    private let calendar = Calendar.laxWeek

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func trip(_ name: String, _ from: Date, _ to: Date, country: TripCountry = .unitedStates) -> Trip {
        Trip(name: name, country: country, departureDate: from, returnDate: to)
    }

    func testDaysAndNightsCountCalendarDays() {
        // Leave Friday morning, back late Sunday: 3 days, 2 nights.
        let weekend = trip("Weekend", date(2026, 10, 16, hour: 6), date(2026, 10, 18, hour: 23))
        XCTAssertEqual(weekend.days(calendar: calendar), 3)
        XCTAssertEqual(weekend.nights(calendar: calendar), 2)

        let dayTrip = trip("Day trip", date(2026, 11, 1, hour: 6), date(2026, 11, 1, hour: 22))
        XCTAssertEqual(dayTrip.days(calendar: calendar), 1)
        XCTAssertEqual(dayTrip.nights(calendar: calendar), 0)

        let backwards = trip("Typo", date(2026, 11, 5), date(2026, 11, 1))
        XCTAssertEqual(backwards.days(calendar: calendar), 1, "a return before the departure counts as one day")
        XCTAssertEqual(backwards.calendarDays(calendar: calendar).count, 1)
    }

    func testHotelNights() {
        var t = trip("Weekend", date(2026, 10, 15), date(2026, 10, 18))
        XCTAssertFalse(t.hasHotel)
        XCTAssertEqual(t.hotelNights(calendar: calendar), 0)

        t.hotelName = "Harbour Inn"
        XCTAssertEqual(t.hotelNights(calendar: calendar), 3, "with no check-in or check-out, the hotel follows the trip's dates")

        t.hotelCheckIn = date(2026, 10, 16, hour: 15)
        XCTAssertEqual(t.hotelNights(calendar: calendar), 2)
        t.hotelCheckOut = date(2026, 10, 17, hour: 11)
        XCTAssertEqual(t.hotelNights(calendar: calendar), 1)
    }

    func testDaysInTheUSCountEachDayOnce() {
        let trips = [
            trip("Fall Brawl", date(2026, 10, 15), date(2026, 10, 18)),          // 4 days
            trip("Overlap", date(2026, 10, 18), date(2026, 10, 19)),             // 1 new day (the 18th is shared)
            trip("Ontario", date(2026, 11, 6), date(2026, 11, 8), country: .canada),
            trip("New Year", date(2026, 12, 30), date(2027, 1, 2)),              // 2 days in 2026, 2 in 2027
            trip("Summer", date(2027, 7, 30), date(2027, 8, 2))                  // 2 days in the 2026/27 season, 2 in 2027/28
        ]
        let year2026 = TripMath.usDays(trips, in: TripMath.interval(year: 2026, calendar: calendar), calendar: calendar)
        XCTAssertEqual(year2026, USDaysSummary(days: 7, trips: 3))
        let year2027 = TripMath.usDays(trips, in: TripMath.interval(year: 2027, calendar: calendar), calendar: calendar)
        XCTAssertEqual(year2027, USDaysSummary(days: 6, trips: 2))
        let season = TripMath.usDays(trips, in: TripMath.interval(season: 2026, calendar: calendar), calendar: calendar)
        XCTAssertEqual(season, USDaysSummary(days: 11, trips: 4))
        XCTAssertEqual(TripMath.usDays([], in: TripMath.interval(year: 2026, calendar: calendar), calendar: calendar).days, 0)
    }

    func testTripSummaryAddsUpItsExpenses() {
        var data = Fixtures.season()
        var t = trip("Fall Brawl", date(2026, 10, 15, hour: 7), date(2026, 10, 18, hour: 21))
        t.hotelName = "Harbour Inn"
        t.budget = 1200
        data.trips.append(t)
        data.expenses += [
            Expense(date: date(2026, 9, 10), title: "Entry fee", category: .tournamentFees, amount: 400, tripID: t.id),
            Expense(date: date(2026, 10, 18), title: "Hotel", category: .lodging, amount: 690, tripID: t.id),
            Expense(date: date(2026, 10, 16), title: "Groceries", category: .food, amount: 85.5, tripID: t.id),
            Expense(date: date(2026, 10, 17), title: "Team dinner", category: .food, amount: 40, tripID: t.id),
            Expense(date: date(2026, 10, 15), title: "Tolls", category: .other, amount: 22, tripID: t.id)
        ]

        let summary = TripMath.summary(t, in: data, calendar: calendar)
        XCTAssertEqual(summary.expenses.count, 5, "only this trip's expenses")
        XCTAssertEqual(summary.expenses.first?.title, "Hotel", "newest first")
        XCTAssertEqual(summary.spent, 1237.5)
        XCTAssertEqual(summary.spent(on: .food), 125.5)
        XCTAssertEqual(summary.spent(on: .travel), 0)
        XCTAssertEqual(summary.byCategory.map(\.category), [.lodging, .tournamentFees, .food, .other])
        XCTAssertEqual(summary.days, 4)
        XCTAssertEqual(summary.nights, 3)
        XCTAssertEqual(summary.lodgingPerNight, 230)
        XCTAssertEqual(try XCTUnwrap(summary.foodPerDay), 31.375, accuracy: 0.0001)
        XCTAssertTrue(summary.isOverBudget)
        XCTAssertEqual(summary.remaining, -37.5)

        let empty = TripMath.summary(Fixtures.season().trips[0], in: Fixtures.season(), calendar: calendar)
        XCTAssertEqual(empty.spent, 0)
        XCTAssertNil(empty.lodgingPerNight)
        XCTAssertNil(empty.foodPerDay)
        XCTAssertFalse(empty.isOverBudget)
    }

    func testTripsBySeason() {
        var data = Fixtures.season()
        data.trips.append(trip("Spring", date(2027, 4, 2), date(2027, 4, 4)))
        data.trips.append(trip("Next summer", date(2027, 8, 20), date(2027, 8, 22)))
        XCTAssertEqual(data.trips(in: 2026).map(\.name), ["Fall showcase", "Spring"])
        XCTAssertEqual(data.trips(in: 2027).map(\.name), ["Next summer"])
        XCTAssertTrue(data.budgetSeasons(current: 2026).contains(2027))
        XCTAssertEqual(data.trip(id: data.trips[0].id)?.name, "Fall showcase")
    }

    func testTripFromAnEvent() {
        let event = SeasonEvent(kind: .tournament, title: "Fall Brawl", team: "Club 2031", date: date(2026, 10, 16, hour: 8),
                                endDate: date(2026, 10, 18, hour: 17), location: "Baltimore, MD")
        let t = Trip(event: event, programID: "club")
        XCTAssertEqual(t.name, "Fall Brawl")
        XCTAssertEqual(t.destination, "Baltimore, MD")
        XCTAssertEqual(t.country, .unitedStates)
        XCTAssertEqual(t.eventID, event.id)
        XCTAssertEqual(t.programID, "club")
        XCTAssertEqual(t.season, 2026)
        XCTAssertEqual(t.days(calendar: calendar), 3)

        let oneDay = Trip(event: SeasonEvent(kind: .camp, title: "Camp", team: "", date: date(2026, 7, 4), location: "Oakville, ON"))
        XCTAssertEqual(oneDay.country, .canada)
        XCTAssertEqual(oneDay.returnDate, oneDay.departureDate)
        XCTAssertEqual(oneDay.season, 2025, "a July trip belongs to the season that started the August before")
    }

    func testCountryFromAPlace() {
        XCTAssertEqual(TripCountry.guess(from: "Baltimore, MD"), .unitedStates)
        XCTAssertEqual(TripCountry.guess(from: "San Diego, CA"), .unitedStates)
        XCTAssertEqual(TripCountry.guess(from: "Lake Placid, NY 12946"), .unitedStates, "digits after the state are skipped")
        XCTAssertEqual(TripCountry.guess(from: "Orlando, Florida, USA"), .unitedStates)
        XCTAssertEqual(TripCountry.guess(from: "Burnaby, BC"), .canada)
        XCTAssertEqual(TripCountry.guess(from: "Toronto, Ontario, Canada"), .canada)
        XCTAssertNil(TripCountry.guess(from: "Home field"))
        XCTAssertNil(TripCountry.guess(from: "ON"), "a bare word isn't a place")
    }

    func testTripsRoundTripThroughJSON() throws {
        let data = Fixtures.season()
        let decoded = try AppData.decoder.decode(AppData.self, from: AppData.encoder.encode(data))
        XCTAssertEqual(decoded.trips, data.trips)

        // Files saved before trips have none.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: AppData.encoder.encode(data)) as? [String: Any])
        object["trips"] = nil
        let old = try AppData.decoder.decode(AppData.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(old.trips.isEmpty)
        XCTAssertTrue(old.expenses.allSatisfy { $0.tripID == nil })
    }

    func testValuesFromANewerVersionStillLoad() throws {
        let expense = """
        {"id": "3f2504e0-4f89-11d3-9a0c-0305e82c3301", "date": "2026-10-01T12:00:00Z", "title": "Parking", "category": "parking",
         "amount": 12, "tripID": "3f2504e0-4f89-11d3-9a0c-0305e82c3302", "currency": "USD"}
        """
        let decoded = try AppData.decoder.decode(Expense.self, from: Data(expense.utf8))
        XCTAssertEqual(decoded.category, .other, "an unknown category reads as other")
        XCTAssertEqual(decoded.tripID, UUID(uuidString: "3f2504e0-4f89-11d3-9a0c-0305e82c3302"))

        let trip = """
        {"id": "3f2504e0-4f89-11d3-9a0c-0305e82c3302", "name": "Fall Brawl", "departureDate": "2026-10-15T12:00:00Z",
         "travelMode": "hovercraft", "country": "MX"}
        """
        let t = try AppData.decoder.decode(Trip.self, from: Data(trip.utf8))
        XCTAssertEqual(t.travelMode, .other)
        XCTAssertEqual(t.country, .other)
        XCTAssertEqual(t.returnDate, t.departureDate)
        XCTAssertEqual(t.season, 2026)
        XCTAssertEqual(t.hotelName, "")
    }

    func testBlankSeasonKeepsTripsWithoutTheirEvents() {
        let season = Fixtures.season()
        let blank = season.blankSeason()
        XCTAssertEqual(blank.trips.map(\.id), season.trips.map(\.id))
        XCTAssertNotNil(season.trips[0].eventID)
        XCTAssertNil(blank.trips[0].eventID, "the events go, so the link does too")
        XCTAssertEqual(blank.trips[0].hotelName, "Harbour Inn")
    }

    // MARK: - Cloud rows

    func testTripRowsRoundTrip() {
        var data = Fixtures.season()
        data.expenses.append(Expense(date: Fixtures.day(60), title: "Hotel", category: .lodging, amount: 460, programID: "club",
                                     tripID: data.trips[0].id))
        let snapshot = ProfileSnapshot(data)
        XCTAssertEqual(snapshot.trips.count, 1)
        XCTAssertEqual(snapshot.trips[0].eventID, data.events[1].id)
        XCTAssertEqual(snapshot.expenses.last?.tripID, data.trips[0].id)

        let rebuilt = snapshot.appData
        XCTAssertEqual(rebuilt.trips, data.trips)
        XCTAssertEqual(rebuilt.expenses.first { $0.category == .lodging }?.tripID, data.trips[0].id)
        XCTAssertEqual(ProfileSnapshot(rebuilt), snapshot)
    }

    func testTripRowsOnlyPointAtRowsThatExist() {
        var data = Fixtures.season()
        data.trips[0].programID = "gone"
        data.trips[0].eventID = UUID()
        data.trips[0].departureDate = Fixtures.day(61)
        data.trips[0].returnDate = Fixtures.day(59)
        data.trips[0].hotelCheckIn = Fixtures.day(61)
        data.trips[0].hotelCheckOut = Fixtures.day(60)
        data.trips[0].season = 3000
        data.trips[0].budget = -5
        data.expenses[0].tripID = UUID()
        let row = ProfileSnapshot(data).trips[0]
        XCTAssertNil(row.programID, "a link to a deleted program would fail the foreign key")
        XCTAssertNil(row.eventID, "so would a link to a deleted event")
        XCTAssertEqual(row.departsAt, Timestamp(Fixtures.day(59)), "dates typed backwards are turned around")
        XCTAssertEqual(row.returnsAt, Timestamp(Fixtures.day(61)))
        XCTAssertEqual(row.hotelCheckIn, Timestamp(Fixtures.day(60)))
        XCTAssertEqual(row.hotelCheckOut, Timestamp(Fixtures.day(61)))
        XCTAssertEqual(row.season, 2026)
        XCTAssertEqual(row.budget, 0)
        XCTAssertNil(ProfileSnapshot(data).expenses[0].tripID, "and so would a link to a deleted trip")
    }

    // MARK: - Merge

    /// A trip edited here while its event was deleted on another device keeps the edit and drops the link, so the
    /// write doesn't fail the foreign key.
    func testTripEditedHereWhileItsEventWasDeletedThere() {
        let season = Fixtures.season()
        let base = ProfileSnapshot(season)
        var local = season
        local.trips[0].hotelName = "Lakeside Hotel"
        var remote = base
        remote.events.removeAll { $0.id == season.events[1].id }
        remote.trips[0].eventID = nil  // what the database's "on delete set null" does
        let outcome = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: remote)
        XCTAssertEqual(outcome.merged.trips.first?.hotelName, "Lakeside Hotel")
        XCTAssertNil(outcome.merged.trips.first?.eventID)
        XCTAssertEqual(outcome.changes.trips.upserts.count, 1)
        XCTAssertNil(outcome.changes.trips.upserts.first?.eventID)
        XCTAssertTrue(outcome.changes.events.isEmpty)
    }

    func testExpenseEditedHereWhileItsTripWasDeletedThere() {
        var season = Fixtures.season()
        season.expenses.append(Expense(date: Fixtures.day(60), title: "Hotel", category: .lodging, amount: 460, tripID: season.trips[0].id))
        let base = ProfileSnapshot(season)
        var local = season
        local.expenses[2].note = "Two rooms"
        var remote = base
        remote.trips.removeAll()
        remote.expenses[2].tripID = nil
        let outcome = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: remote)
        XCTAssertTrue(outcome.merged.trips.isEmpty, "the trip stays deleted")
        let expense = outcome.merged.expenses.first { $0.title == "Hotel" }
        XCTAssertEqual(expense?.note, "Two rooms")
        XCTAssertNil(expense?.tripID)
        XCTAssertEqual(outcome.changes.expenses.upserts.map(\.note), ["Two rooms"])
        XCTAssertNil(outcome.changes.expenses.upserts.first?.tripID)
    }

    func testTripChangesAreMergedLikeOtherRows() {
        let season = Fixtures.season()
        let base = ProfileSnapshot(season)
        var local = season
        local.trips[0].travelDetails = "Flying from YYZ"
        local.trips.append(Trip(name: "Spring", departureDate: Fixtures.day(200), returnDate: Fixtures.day(202)))
        let outcome = ProfileMerge.merge(base: base, local: ProfileSnapshot(local), remote: base)
        XCTAssertEqual(Set(outcome.changes.trips.upserts.map(\.name)), ["Fall showcase", "Spring"])
        XCTAssertFalse(outcome.changes.isEmpty)

        var deleted = season
        deleted.trips.removeAll()
        let removal = ProfileMerge.merge(base: base, local: ProfileSnapshot(deleted), remote: base)
        XCTAssertEqual(removal.changes.trips.deletes, [season.trips[0].id])
        XCTAssertTrue(removal.merged.trips.isEmpty)
    }
}
