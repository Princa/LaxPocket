import XCTest
@testable import LaxPocketCore

final class CurrencyTests: XCTestCase {
    func testConvertsToCAD() {
        XCTAssertEqual(ExchangeRate.cad(200, in: .usd, rate: 1.38), 276)
        XCTAssertEqual(ExchangeRate.cad(85.5, in: .usd, rate: 1.3725), 117.35, "to the cent")
        XCTAssertEqual(ExchangeRate.cad(85.5, in: .cad, rate: 1.38), 85.5)
        XCTAssertEqual(ExchangeRate.shown(276, in: .usd, rate: 1.38), 200, accuracy: 0.0001)
        XCTAssertEqual(ExchangeRate.shown(276, in: .cad, rate: 1.38), 276)
    }

    func testRatesAreKeptInRange() {
        XCTAssertEqual(ExchangeRate.normalized(1.371234), 1.3712)
        XCTAssertEqual(ExchangeRate.normalized(0), ExchangeRate.defaultUSDToCAD)
        XCTAssertEqual(ExchangeRate.normalized(-1), ExchangeRate.defaultUSDToCAD)
        XCTAssertEqual(ExchangeRate.normalized(.nan), ExchangeRate.defaultUSDToCAD)
        XCTAssertEqual(ExchangeRate.normalized(13.8), 3, "a misplaced decimal is capped")
    }

    func testAnExpensePaidInUSD() {
        var expense = Expense(date: Fixtures.day(0), title: "Hotel", category: .lodging, amount: 0)
        XCTAssertEqual(expense.currency, .cad)
        XCTAssertNil(expense.exchangeRate)
        expense.setPaid(500, in: .usd, rate: 1.38)
        XCTAssertEqual(expense.amount, 690, "budgets and totals use the CAD amount")
        XCTAssertEqual(expense.paidAmount, 500)
        XCTAssertEqual(try XCTUnwrap(expense.exchangeRate), 1.38, accuracy: 0.0001)
        expense.setPaid(120, in: .cad, rate: 1.38)
        XCTAssertEqual(expense.amount, 120)
        XCTAssertNil(expense.originalAmount)
        XCTAssertEqual(expense.paidAmount, 120)

        let inconsistent = Expense(date: Fixtures.day(0), title: "x", category: .food, amount: 10, currency: .usd)
        XCTAssertEqual(inconsistent.currency, .cad, "US dollars without what was paid is CAD")
    }

    func testTotalsAddUpInCAD() {
        var data = Fixtures.season()
        var hotel = Expense(date: Fixtures.day(60), title: "Hotel", category: .lodging, amount: 0, tripID: data.trips[0].id)
        hotel.setPaid(500, in: .usd, rate: 1.38)
        data.expenses.append(hotel)
        XCTAssertEqual(BudgetMath.season(2026, in: data).summary.spent, 1850 + 320.5 + 690)
        XCTAssertEqual(TripMath.summary(data.trips[0], in: data).spent(on: .lodging), 690)
    }

    func testChangingTheRate() {
        var data = Fixtures.season()
        XCTAssertEqual(data.profile.usdToCAD, ExchangeRate.defaultUSDToCAD)
        var hotel = Expense(date: Fixtures.day(60), title: "Hotel", category: .lodging, amount: 0)
        hotel.setPaid(500, in: .usd, rate: 1.38)
        data.expenses.append(hotel)
        XCTAssertEqual(data.usdExpenses.count, 1)

        data.setUSDToCAD(1.40, reconvert: false)
        XCTAssertEqual(data.profile.usdToCAD, 1.4)
        XCTAssertEqual(data.expenses.last?.amount, 690, "expenses keep the rate they were recorded at")
        data.setUSDToCAD(1.42, reconvert: true)
        XCTAssertEqual(data.expenses.last?.amount, 710)
        XCTAssertEqual(data.expenses.last?.originalAmount, 500)
        XCTAssertEqual(data.expenses.first?.amount, 1850, "CAD expenses don't change")
    }

    func testOlderFilesAreCAD() throws {
        let old = """
        {"id": "3f2504e0-4f89-11d3-9a0c-0305e82c3301", "date": "2026-10-01T12:00:00Z", "title": "Fee", "category": "teamFees", "amount": 12}
        """
        let expense = try AppData.decoder.decode(Expense.self, from: Data(old.utf8))
        XCTAssertEqual(expense.currency, .cad)
        XCTAssertNil(expense.originalAmount)

        let newer = """
        {"id": "3f2504e0-4f89-11d3-9a0c-0305e82c3301", "date": "2026-10-01T12:00:00Z", "title": "Fee", "category": "teamFees",
         "amount": 12, "currency": "EUR", "originalAmount": 8}
        """
        XCTAssertEqual(try AppData.decoder.decode(Expense.self, from: Data(newer.utf8)).currency, .cad, "an unknown currency reads as CAD")

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: AppData.encoder.encode(Fixtures.season())) as? [String: Any])
        var profile = try XCTUnwrap(object["profile"] as? [String: Any])
        profile["usdToCAD"] = nil
        object["profile"] = profile
        let data = try AppData.decoder.decode(AppData.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(data.profile.usdToCAD, ExchangeRate.defaultUSDToCAD)
    }

    func testCurrencyRoundTripsThroughRows() throws {
        var data = Fixtures.season()
        data.profile.usdToCAD = 1.3725
        var hotel = Expense(date: Fixtures.day(60), title: "Hotel", category: .lodging, amount: 0)
        hotel.setPaid(499.999, in: .usd, rate: 1.3725)
        data.expenses.append(hotel)
        let snapshot = ProfileSnapshot(data)
        XCTAssertEqual(snapshot.profile.usdToCAD, 1.3725)
        let row = try XCTUnwrap(snapshot.expenses.last)
        XCTAssertEqual(row.currency, .usd)
        XCTAssertEqual(row.originalAmount, 500, "rounded to the cent like the database")
        XCTAssertEqual(snapshot.expenses.first?.currency, .cad)
        XCTAssertNil(snapshot.expenses.first?.originalAmount)

        let rebuilt = snapshot.appData
        XCTAssertEqual(rebuilt.profile.usdToCAD, 1.3725)
        XCTAssertEqual(rebuilt.expenses.last?.paidAmount, 500)
        XCTAssertEqual(rebuilt.expenses.last?.currency, .usd)
        XCTAssertEqual(ProfileSnapshot(rebuilt), snapshot)

        // Rows and sync records from before currencies.
        let json = """
        [{"id": "3f2504e0-4f89-11d3-9a0c-0305e82c3301", "profile_id": "10000000-0000-4000-8000-000000000001", "spent_at": "2027-03-01T12:00:00+00:00",
          "title": "Stick", "category": "equipment", "amount": 250, "note": ""}]
        """
        let old = try XCTUnwrap(JSONDecoder().decode([ExpenseRow].self, from: Data(json.utf8)).first)
        XCTAssertEqual(old.currency, .cad)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: AppData.encoder.encode(snapshot)) as? [String: Any])
        var profile = try XCTUnwrap(object["profile"] as? [String: Any])
        profile["usd_to_cad"] = nil
        object["profile"] = profile
        let record = try AppData.decoder.decode(ProfileSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(record.profile.usdToCAD, ExchangeRate.defaultUSDToCAD)
    }
}
