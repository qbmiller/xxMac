import Foundation

struct CalculatorExpressionEvaluator {
    struct Result: Equatable {
        let expression: String
        let value: String
    }

    static func evaluate(_ input: String) -> Result? {
        let expression = normalizedExpression(input)
        guard isCalculatorCandidate(expression) else { return nil }

        var parser = Parser(expression)
        guard let value = parser.parse(), value.isFinite else { return nil }

        return Result(expression: expression, value: formatted(value))
    }

    private static func normalizedExpression(_ input: String) -> String {
        input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "＋", with: "+")
            .replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "＊", with: "*")
            .replacingOccurrences(of: "／", with: "/")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
    }

    private static func isCalculatorCandidate(_ expression: String) -> Bool {
        guard !expression.isEmpty else { return false }

        let allowed = CharacterSet(charactersIn: "0123456789.+-*/() ")
        guard expression.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        guard expression.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) }) else { return false }

        if expression.contains("(") || expression.contains(")") { return true }
        if expression.first == "-" || expression.first == "+" { return true }
        return expression.contains("+") || expression.contains("-") || expression.contains("*") || expression.contains("/")
    }

    private static func formatted(_ value: Double) -> String {
        let normalized = abs(value) < 0.0000000001 ? 0 : value
        if normalized.rounded() == normalized, abs(normalized) <= 9_000_000_000_000_000 {
            return String(Int64(normalized))
        }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 10
        return formatter.string(from: NSNumber(value: normalized)) ?? String(normalized)
    }
}

private struct Parser {
    private let characters: [Character]
    private var index = 0

    init(_ expression: String) {
        characters = Array(expression)
    }

    mutating func parse() -> Double? {
        guard let value = parseExpression() else { return nil }
        skipSpaces()
        return isAtEnd ? value : nil
    }

    private mutating func parseExpression() -> Double? {
        guard var value = parseTerm() else { return nil }

        while true {
            skipSpaces()
            if consume("+") {
                guard let rhs = parseTerm() else { return nil }
                value += rhs
            } else if consume("-") {
                guard let rhs = parseTerm() else { return nil }
                value -= rhs
            } else {
                return value
            }
        }
    }

    private mutating func parseTerm() -> Double? {
        guard var value = parseFactor() else { return nil }

        while true {
            skipSpaces()
            if consume("*") {
                guard let rhs = parseFactor() else { return nil }
                value *= rhs
            } else if consume("/") {
                guard let rhs = parseFactor(), rhs != 0 else { return nil }
                value /= rhs
            } else {
                return value
            }
        }
    }

    private mutating func parseFactor() -> Double? {
        skipSpaces()

        if consume("+") {
            return parseFactor()
        }
        if consume("-") {
            guard let value = parseFactor() else { return nil }
            return -value
        }
        if consume("(") {
            guard let value = parseExpression() else { return nil }
            skipSpaces()
            guard consume(")") else { return nil }
            return value
        }

        return parseNumber()
    }

    private mutating func parseNumber() -> Double? {
        skipSpaces()
        let start = index
        var hasDigit = false
        var hasDecimalPoint = false

        while !isAtEnd {
            let character = characters[index]
            if character.isNumber {
                hasDigit = true
                index += 1
            } else if character == ".", !hasDecimalPoint {
                hasDecimalPoint = true
                index += 1
            } else {
                break
            }
        }

        guard hasDigit else { return nil }
        return Double(String(characters[start..<index]))
    }

    private mutating func skipSpaces() {
        while !isAtEnd, characters[index] == " " {
            index += 1
        }
    }

    private mutating func consume(_ character: Character) -> Bool {
        guard !isAtEnd, characters[index] == character else { return false }
        index += 1
        return true
    }

    private var isAtEnd: Bool {
        index >= characters.count
    }
}
