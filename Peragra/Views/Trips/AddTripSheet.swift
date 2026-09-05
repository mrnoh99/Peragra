import SwiftUI
import SwiftData

struct AddTripSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private static let emojiChoices = ["✈️", "🗺️", "🏖️", "🏙️", "⛰️", "🍜", "🎡", "🚆"]

    @State private var name = ""
    @State private var destination = ""
    @State private var coverEmoji = AddTripSheet.emojiChoices[0]

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !destination.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Board") {
                    TextField("Board name (e.g. Tokyo Spring Trip)", text: $name)
                    TextField("Destination (e.g. Tokyo, Japan)", text: $destination)
                }

                Section("Cover icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                        ForEach(Self.emojiChoices, id: \.self) { emoji in
                            Button {
                                coverEmoji = emoji
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 26))
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(coverEmoji == emoji ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(coverEmoji == emoji ? Color.accentColor : .clear, lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("New Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createTrip() }
                        .disabled(!canSubmit)
                }
            }
        }
    }

    private func createTrip() {
        let trip = Trip(
            name: name.trimmingCharacters(in: .whitespaces),
            destination: destination.trimmingCharacters(in: .whitespaces),
            coverEmoji: coverEmoji
        )
        modelContext.insert(trip)
        _ = PlaceCollection.ensureFavoritesList(for: trip, context: modelContext)
        _ = PlaceCollection.ensureVisitedList(for: trip, context: modelContext)
        dismiss()
    }
}

#Preview {
    AddTripSheet()
        .modelContainer(for: [Trip.self, Place.self, PlaceCollection.self], inMemory: true)
}
