//
//  dayDetailView.swift
//  Journey App
//
//  Created by Yuyang Hu on 8/24/25.
//
import SwiftUI

// MARK: - Day Details

struct DayDetailView: View {
    @EnvironmentObject var auth: AuthService
    let date: Date
    private let calendar = Calendar.autoupdatingCurrent
    @State private var displaySummary: String = "Loading..."

    var title: String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = .autoupdatingCurrent
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: date)
    }
    var lookupDate: String {
        let f = DateFormatter()
        f.calendar  = calendar
        f.locale = .autoupdatingCurrent
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .bold()
                .padding(.top)
            Text(displaySummary)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .navigationTitle("Day")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                let summaries = try await auth.getSummaries(for: lookupDate)
                displaySummary = summaries.first ?? "Nothing to see here..."
            } catch URLError.badURL {
                displaySummary = "Server error. Please try again later."
            } catch URLError.badServerResponse{
                displaySummary = "Nothing to see here..."
            } catch {
                displaySummary = "Nothing to see here..."
            }
        }
    }
}
