//
//  isoDateString.swift
//  Journey App
//
//  Created by Yuyang Hu on 8/24/25.
//
import Foundation

//Converts the current date into a string of form yyyy-MM-dd
func isoDateString(for date: Date = Date()) -> String {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .iso8601)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
}
