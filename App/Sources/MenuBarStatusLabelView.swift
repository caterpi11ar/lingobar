import SwiftUI

struct MenuBarStatusLabelView: View {
    let symbolName: String
    let text: String
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbolName)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, options: .repeating, isActive: isLoading)
            Text(text)
                .lineLimit(1)
        }
    }
}
