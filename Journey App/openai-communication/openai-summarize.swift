import Foundation
import SwiftUI

func summarizeGPT(_ messages: [Message], completion: @escaping (String?) -> Void) {
    guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else { return }
    var summarize: String = ""
    for message in messages{
        if message.isFromCurrentUser {
            summarize += message.text + " "
        }
    }
    let body: [String: Any] = [
        "model": "gpt-5-mini", // use gpt-5-mini when available
        "messages": [
            ["role": "system", "content": "Summarize the given messages into a journal entry, return only the summary, no date, no response, nothing else"],
            ["role": "user", "content": summarize]
        ]
    ]
    let jsonData = try? JSONSerialization.data(withJSONObject: body)
    let api_key = "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"
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.addValue("Bearer \(ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? api_key)", // Use environment variable or fallback to hardcoded key
                     forHTTPHeaderField: "Authorization")
    request.httpBody = jsonData

    URLSession.shared.dataTask(with: request) { data, response, error in
        guard let data = data, error == nil else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }
        if let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = result["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String {
            completion(content)
        } else {
            completion(nil)
        }
    }.resume()
}
