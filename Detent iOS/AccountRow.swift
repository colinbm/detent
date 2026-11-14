import SwiftUI

struct AccountRow: View {
    let account: Account
    let date: Date
    let copied: Bool
    let copy: () -> Void

    var body: some View {
        let remaining = TOTP.secondsRemaining(period: account.period, at: date)
        let code = account.code(at: date)
        let half = code.index(code.startIndex, offsetBy: code.count / 2)
        let expiring = remaining <= 5

        Button(action: copy) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.issuer.isEmpty ? account.name : account.issuer)
                        .font(.headline)
                        .lineLimit(1)
                    if !account.issuer.isEmpty && !account.name.isEmpty {
                        Text(account.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text("\(code[..<half]) \(code[half...])")
                        .font(.system(.largeTitle, design: .rounded).monospacedDigit().weight(.medium))
                        .foregroundStyle(expiring ? .red : .primary)
                        .contentTransition(.numericText())
                        .padding(.top, 2)
                }
                Spacer()
                Countdown(fraction: remaining / Double(account.period), expiring: expiring, copied: copied)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(account.label), code \(code)")
        .accessibilityHint("Copies the code")
    }
}

/// A ring that empties as the code ages. Shows a tick for a moment after copying.
private struct Countdown: View {
    let fraction: Double
    let expiring: Bool
    let copied: Bool

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 4)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(expiring ? Color.red : Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: fraction)
            if copied {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tint)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}
