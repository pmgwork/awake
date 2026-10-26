//
//  JSONCTextEditor.swift
//  Awake
//

import Foundation

/// Edits top-level members of a JSON/JSONC object in place, so comments,
/// trailing commas, key order, and formatting elsewhere in a user's
/// configuration survive. Structural characters are ASCII and never appear
/// inside multi-byte UTF-8 sequences, so scanning bytes is safe.
nonisolated struct JSONCTextEditor {
    private struct Member {
        let key: String
        let start: Int
        let valueStart: Int
        let valueEnd: Int
    }

    private var bytes: [UInt8]

    init(_ text: String) {
        bytes = Array(text.utf8)
    }

    var text: String { String(decoding: bytes, as: UTF8.self) }

    /// Sets (non-nil) or removes (nil) each top-level key. Returns nil when
    /// the text is not an object this scanner understands.
    static func applying(_ changes: [(key: String, value: Any?)], to text: String) -> String? {
        var editor = JSONCTextEditor(text)
        for change in changes {
            guard editor.set(change.key, to: change.value) else { return nil }
        }
        return editor.text
    }

    private mutating func set(_ key: String, to value: Any?) -> Bool {
        guard let (rootOpen, members) = scanRoot() else { return false }
        let index = members.firstIndex { $0.key == key }
        guard let value else {
            guard let index else { return true }
            let member = members[index]
            if let comma = commaAfter(member.valueEnd) {
                bytes.removeSubrange(member.start...comma)
            } else if index > 0 {
                // Last member: drop the separator before it instead.
                bytes.removeSubrange(members[index - 1].valueEnd..<member.valueEnd)
            } else {
                bytes.removeSubrange(member.start..<member.valueEnd)
            }
            return true
        }
        guard JSONSerialization.isValidJSONObject([value]),
              let encodedValue = try? JSONSerialization.data(
                withJSONObject: value,
                options: [.withoutEscapingSlashes, .fragmentsAllowed]
              ),
              let encodedKey = try? JSONSerialization.data(
                withJSONObject: key,
                options: [.withoutEscapingSlashes, .fragmentsAllowed]
              ) else { return false }
        if let index {
            let member = members[index]
            bytes.replaceSubrange(member.valueStart..<member.valueEnd, with: Array(encodedValue))
        } else {
            var inserted = Array("\n  ".utf8) + Array(encodedKey) + Array(": ".utf8) + Array(encodedValue)
            if !members.isEmpty { inserted += Array(",".utf8) }
            bytes.insert(contentsOf: inserted, at: rootOpen + 1)
        }
        return true
    }

    private func scanRoot() -> (rootOpen: Int, members: [Member])? {
        var index = skipTrivia(0)
        guard index < bytes.count, bytes[index] == UInt8(ascii: "{") else { return nil }
        let rootOpen = index
        var members: [Member] = []
        index += 1
        while true {
            index = skipTrivia(index)
            guard index < bytes.count else { return nil }
            switch bytes[index] {
            case UInt8(ascii: "}"):
                return (rootOpen, members)
            case UInt8(ascii: ","):
                index += 1
            case UInt8(ascii: "\""):
                let start = index
                guard let keyEnd = skipString(index),
                      let key = try? JSONSerialization.jsonObject(
                        with: Data(bytes[start..<keyEnd]),
                        options: .fragmentsAllowed
                      ) as? String else { return nil }
                index = skipTrivia(keyEnd)
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { return nil }
                let valueStart = skipTrivia(index + 1)
                guard let valueEnd = skipValue(valueStart) else { return nil }
                members.append(Member(key: key, start: start, valueStart: valueStart, valueEnd: valueEnd))
                index = valueEnd
            default:
                return nil
            }
        }
    }

    private func commaAfter(_ index: Int) -> Int? {
        let next = skipTrivia(index)
        return next < bytes.count && bytes[next] == UInt8(ascii: ",") ? next : nil
    }

    /// Skips whitespace and comments.
    func skipTrivia(_ start: Int) -> Int {
        var index = start
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                index += 1
            } else if byte == UInt8(ascii: "/"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "/") {
                index += 2
                while index < bytes.count, bytes[index] != 0x0A { index += 1 }
            } else if byte == UInt8(ascii: "/"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "*") {
                index += 2
                while index < bytes.count,
                      !(bytes[index] == UInt8(ascii: "*") && index + 1 < bytes.count && bytes[index + 1] == UInt8(ascii: "/")) {
                    index += 1
                }
                index = min(index + 2, bytes.count)
            } else {
                break
            }
        }
        return index
    }

    /// Returns the index after the closing quote.
    private func skipString(_ start: Int) -> Int? {
        var index = start + 1
        while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: "\\"): index += 2
            case UInt8(ascii: "\""): return index + 1
            default: index += 1
            }
        }
        return nil
    }

    private func skipValue(_ start: Int) -> Int? {
        guard start < bytes.count else { return nil }
        switch bytes[start] {
        case UInt8(ascii: "\""):
            return skipString(start)
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            var depth = 0
            var index = start
            while index < bytes.count {
                let trivia = skipTrivia(index)
                if trivia != index {
                    index = trivia
                    continue
                }
                switch bytes[index] {
                case UInt8(ascii: "\""):
                    guard let end = skipString(index) else { return nil }
                    index = end
                    continue
                case UInt8(ascii: "{"), UInt8(ascii: "["):
                    depth += 1
                case UInt8(ascii: "}"), UInt8(ascii: "]"):
                    depth -= 1
                    if depth == 0 { return index + 1 }
                default:
                    break
                }
                index += 1
            }
            return nil
        default:
            var index = start
            while index < bytes.count {
                let byte = bytes[index]
                if byte == UInt8(ascii: ",") || byte == UInt8(ascii: "}") || byte == UInt8(ascii: "]")
                    || byte == UInt8(ascii: "/") || byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                    break
                }
                index += 1
            }
            return index > start ? index : nil
        }
    }
}
