import SwiftUI

struct SyncResultView: View {
    struct Summary {
        let avgSkinTempC: Double?
        let maxSkinTempC: Double?
        let avgCoreTempC: Double?
        let maxCoreTempC: Double?
        let readingCount: Int
    }

    enum Outcome {
        case success(Summary)
        case failure(summary: Summary, message: String)
    }

    let outcome: Outcome
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            headline
            statsCard
            Spacer()

            Button(action: onDone) {
                Text("Done")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
        }
        .padding()
    }

    @ViewBuilder
    private var headline: some View {
        switch outcome {
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Session synced")
                .font(.title2.bold())
        case .failure(_, let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text("Sync failed")
                .font(.title2.bold())
            Text("\(message) Your session was saved on this device — retry from the connect screen once you're back online.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private var summary: Summary {
        switch outcome {
        case .success(let summary): return summary
        case .failure(let summary, _): return summary
        }
    }

    private var statsCard: some View {
        VStack(spacing: 12) {
            statRow("Readings", "\(summary.readingCount)")
            statRow("Avg skin temp", formattedTemp(summary.avgSkinTempC))
            statRow("Max skin temp", formattedTemp(summary.maxSkinTempC))
            statRow("Avg core temp", coreTempText(summary.avgCoreTempC))
            statRow("Max core temp", coreTempText(summary.maxCoreTempC))
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.monospacedDigit())
        }
    }

    private func formattedTemp(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f°C", value)
    }

    private func coreTempText(_ value: Double?) -> String {
        value.map { formattedTemp($0) } ?? "Pending sensor calibration data"
    }
}

#Preview {
    SyncResultView(
        outcome: .success(
            .init(avgSkinTempC: 33.4, maxSkinTempC: 34.1, avgCoreTempC: nil, maxCoreTempC: nil, readingCount: 212)
        ),
        onDone: {}
    )
}
