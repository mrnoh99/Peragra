import SwiftUI
import SwiftData

struct EditTripSheet: View {
    @Bindable var trip: Trip
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var destination: String
    @State private var coverEmoji: String

    init(trip: Trip) {
        self.trip = trip
        _name = State(initialValue: trip.name)
        _destination = State(initialValue: trip.destination)
        _coverEmoji = State(initialValue: trip.coverEmoji)
    }

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
                        ForEach(Trip.coverEmojiChoices, id: \.self) { emoji in
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
            .navigationTitle("Edit Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSubmit)
                }
            }
        }
    }

    private func save() {
        trip.name = name.trimmingCharacters(in: .whitespaces)
        trip.destination = destination.trimmingCharacters(in: .whitespaces)
        trip.coverEmoji = coverEmoji
        dismiss()
    }
}

#Preview {
    let trip = Trip(name: "Tokyo Spring Trip", destination: "Tokyo, Japan", coverEmoji: "✈️")
    return EditTripSheet(trip: trip)
        .modelContainer(for: [Trip.self, Place.self, PlaceCollection.self], inMemory: true)
}
