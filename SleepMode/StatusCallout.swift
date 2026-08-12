import SwiftUI

struct StatusCallout: View {
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        Button(action: { onDismiss?() }) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.orange.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help("Dismiss")
    }
}
