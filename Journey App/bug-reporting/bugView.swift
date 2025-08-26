//
//  bugView.swift
//  Journey App
//
//  Created by Yuyang Hu on 8/25/25.
//


import SwiftUI

struct BugView: View {
    @State private var bugText: String = ""
    @State private var isSending = false
    @State private var showThanks = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section(header: Text("Bug Report")) {
                TextEditor(text: $bugText)
                    .frame(height: 200)
                    .padding(4)
                Button(action: {
                    let trimmed = bugText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, !isSending else { return }
                    Task {
                        isSending = true
                        do {
                            try await postBugReport(description: trimmed)
                            bugText = ""
                            isSending = false
                            showThanks = true
                            // Show the thank-you screen briefly, then dismiss back to previous view (ChatView)
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                            dismiss()
                        } catch {
                            isSending = false
                            // You could also present an alert here if desired
                            print("Failed to submit bug:", error)
                        }
                    }
                }) {
                    if isSending {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Send Bug Report")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSending || bugText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 10)
            }
        }
        .navigationTitle("Report a Bug")
        .overlay(
            Group {
                if showThanks {
                    ZStack {
                        Color(.systemBackground).ignoresSafeArea()
                        Text("Thank you for reporting!")
                            .font(.title)
                            .padding()
                    }
                }
            }
        )
    }
}

struct BugView_Previews: PreviewProvider {
    static var previews: some View {
        BugView()
    }
}

enum BugReportError: Error {
    case invalidURL
    case encodingFailed
    case invalidResponse
    case serverError(statusCode: Int)
}

func postBugReport(description: String) async throws {
    // 1. Build URL
    guard let url = URL(string: "https://yourjourney.it.com/bugs/report") else {
        throw BugReportError.invalidURL
    }
    
    let today = isoDateString()
    
    // 3. Build payload
    let payload: [String: Any] = [
        "date": today,
        "description": description,
        "status": "not-fulfilled"
    ]
    print("Posting bug report payload:", payload)
    
    // 4. Encode JSON
    guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
        throw BugReportError.encodingFailed
    }
    
    // 5. Create request
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = bodyData
    
    // 6. Send request
    let (_, response) = try await URLSession.shared.data(for: request)
    
    guard let httpResponse = response as? HTTPURLResponse else {
        throw BugReportError.invalidResponse
    }
    
    guard (200...299).contains(httpResponse.statusCode) else {
        throw BugReportError.serverError(statusCode: httpResponse.statusCode)
    }
}
