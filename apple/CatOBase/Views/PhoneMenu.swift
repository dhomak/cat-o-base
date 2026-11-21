import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// A phone number with links for calling and messaging apps.
struct PhoneNumber {
    let tel: URL
    let sms: URL
    let whatsApp: URL?
    let telegram: URL?

    init?(_ raw: String) {
        let cleaned = raw.filter { "+0123456789".contains($0) }
        let digitCount = cleaned.filter(\.isNumber).count
        guard digitCount >= 3,
              let tel = URL(string: "tel:\(cleaned)"),
              let sms = URL(string: "sms:\(cleaned)")
        else { return nil }
        self.tel = tel
        self.sms = sms

        // WhatsApp and Telegram need the full international number without "+".
        let international = PhoneNumber.international(cleaned)
        whatsApp = international.flatMap { URL(string: "https://wa.me/\($0)") }
        telegram = international.flatMap { URL(string: "https://t.me/+\($0)") }
    }

    /// "+972 3-730-7333" → "97237307333". A local number like "03-730-7333" gets the
    /// country code of the device's region.
    static func international(_ cleaned: String) -> String? {
        if cleaned.hasPrefix("+") { return String(cleaned.dropFirst()) }
        if cleaned.hasPrefix("00") { return String(cleaned.dropFirst(2)) }
        if cleaned.hasPrefix("0") {
            guard let region = Locale.current.region?.identifier,
                  let code = callingCodes[region] else { return nil }
            return code + cleaned.dropFirst()
        }
        return cleaned
    }

    private static let callingCodes: [String: String] = [
        "IL": "972", "US": "1", "CA": "1", "GB": "44", "IE": "353", "DE": "49", "FR": "33",
        "ES": "34", "IT": "39", "NL": "31", "BE": "32", "CH": "41", "AT": "43", "PL": "48",
        "PT": "351", "SE": "46", "NO": "47", "DK": "45", "FI": "358", "CZ": "420",
        "RU": "7", "KZ": "7", "UA": "380", "BY": "375", "GE": "995", "AM": "374",
        "CY": "357", "GR": "30", "TR": "90", "AU": "61", "NZ": "64",
    ]
}

/// The tappable number: a menu to call, text, WhatsApp, Telegram or copy.
struct PhoneMenu: View {
    let phone: String

    var body: some View {
        if let number = PhoneNumber(phone) {
            Menu {
                Link(destination: number.tel) {
                    Label("Call", systemImage: "phone")
                }
                Link(destination: number.sms) {
                    Label("Message", systemImage: "message")
                }
                if let whatsApp = number.whatsApp {
                    Link(destination: whatsApp) {
                        Label("WhatsApp", systemImage: "bubble.left.and.bubble.right")
                    }
                }
                if let telegram = number.telegram {
                    Link(destination: telegram) {
                        Label("Telegram", systemImage: "paperplane")
                    }
                }
                Divider()
                Button {
                    copy(phone)
                } label: {
                    Label("Copy Number", systemImage: "doc.on.doc")
                }
            } label: {
                Label(phone, systemImage: "phone.fill")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .help("Call, message, WhatsApp, Telegram or copy")
        } else if !phone.isEmpty {
            Text(phone).foregroundStyle(.secondary)
        }
    }

    private func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
