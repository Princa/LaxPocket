import SwiftUI
import LaxPocketCore

/// Sets the athlete's exchange rate: what a US dollar costs in Canadian dollars. New US-dollar expenses are converted
/// at it, and the budget screens use it to show amounts in US dollars.
struct ExchangeRateView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var rateText = ""
    @State private var reconvert = false

    private var rate: Double? {
        AmountText.parse(rateText).flatMap { ExchangeRate.range.contains($0) ? $0 : nil }
    }

    var body: some View {
        let usdCount = store.data.usdExpenses.count
        NavigationStack {
            Form {
                Section {
                    LabeledContent("1 USD =") {
                        HStack(spacing: 4) {
                            TextField("1.38", text: $rateText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("CAD").foregroundStyle(AppTheme.caption)
                        }
                    }
                } footer: {
                    if let rate {
                        Text("US$100 is \(Formatters.money(ExchangeRate.cad(100, in: .usd, rate: rate))) CAD. Check your bank or card statement for the rate you actually paid.")
                    } else {
                        Text("Enter a rate between \(ExchangeRate.range.lowerBound.formatted()) and \(ExchangeRate.range.upperBound.formatted()).")
                    }
                }

                if usdCount > 0 {
                    Section {
                        Toggle(usdCount == 1 ? "Update the 1 US-dollar expense" : "Update the \(usdCount) US-dollar expenses", isOn: $reconvert)
                    } footer: {
                        Text(reconvert ? "Their CAD amounts are worked out again at the new rate."
                                       : "They keep the rate they were entered at, so past totals don't change.")
                    }
                }
            }
            .navigationTitle("Exchange rate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let rate { store.setUSDToCAD(rate, reconvert: reconvert) }
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(rate == nil)
                }
            }
            .onAppear {
                if rateText.isEmpty { rateText = AmountText.rate(store.profile.usdToCAD) }
            }
        }
    }
}
