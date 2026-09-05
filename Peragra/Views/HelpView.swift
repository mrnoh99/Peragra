import SwiftUI

/// The in-app user guide, reachable from Settings — a quick reference for
/// what the app does, ending with credits.
struct HelpView: View {
    var body: some View {
        Form {
            section("Boards") {
                Text("Your Boards lists each board you're organizing (what used to be called a \"trip\") — a board is a destination, and the places you save inside it. Tap New Board to create one, and the pencil next to its name to rename it.")
            }
            section("Adding saved places") {
                Text("Inside a board, tap Add Places. Paste an Instagram caption to auto-fill a name and address, upload a screenshot for AI to read, or use Upload On-Site Photos / Take Photo Here to log a place you're standing at right now — that marks it Visited automatically, timestamped to the photo.")
            }
            section("Organizing") {
                Text("Star a place to favorite it, tap the checkmark to mark it visited, or make your own custom list. Search, filter by category, and sort by name or by distance from a place you pick.")
            }
            section("Open in Map") {
                Text("Every place has an Open in Map menu: Google Maps always, plus Naver Map, Kakao Map and Tmap when that place is in Korea.")
            }
            section("All Places") {
                Text("See and edit every saved place across every board in one combined list, from All Places on Your Boards.")
            }
            section("AI place extraction") {
                Text("Optional. Add an API key below (Gateway, Anthropic, OpenAI, Gemini, or Perplexity) to let AI read screenshots and photos and fill in details. Without one, pasted captions are still parsed with free pattern-matching. The AI extracted info language setting controls what language AI writes extracted notes in — names, addresses, and phone numbers are always kept exactly as written.")
            }
            section("Map provider") {
                Text("Free (Apple Maps) needs no key. Switch to Google Maps for a nicer map, or Naver Maps for the most accurate geocoding in Korea, if you add your own key/Client ID.")
            }
            section("Backup & Restore") {
                Text("Back up every board and place to a file you choose, and restore from one later. Automatic Backups lets you pick a folder once and Peragra keeps a fresh backup there for you, checked daily or weekly whenever you open the app.")
            }
            Section {
                Text("Peragra — developed by JaiSung Noh, MD. · Version 1.0 · Build 2 · 2026")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("User Guide")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        Section(title) {
            content()
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        HelpView()
    }
}
