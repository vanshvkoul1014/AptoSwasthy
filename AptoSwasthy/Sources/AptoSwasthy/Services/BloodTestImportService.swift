import Foundation
import PDFKit

final class BloodTestImportService: @unchecked Sendable {
    static let shared = BloodTestImportService()

    private init() {}

    func importPDF(at url: URL) throws -> BloodTest {
        guard let pdf = PDFDocument(url: url) else {
            throw BloodTestError.cannotOpenPDF
        }

        var fullText = ""
        for i in 0..<pdf.pageCount {
            if let page = pdf.page(at: i) {
                fullText += page.string ?? ""
                fullText += "\n"
            }
        }

        let biomarkers = extractBiomarkers(from: fullText)
        let testDate = extractDate(from: fullText)
        let labName = extractLabName(from: fullText)

        return BloodTest(
            testDate: testDate,
            labName: labName,
            biomarkers: biomarkers,
            rawText: fullText
        )
    }

    private func extractBiomarkers(from text: String) -> [BloodBiomarker] {
        var results: [BloodBiomarker] = []
        let lines = text.components(separatedBy: .newlines)

        let patterns: [(name: String, aliases: [String])] = [
            ("Glucose", ["glucose", "fasting glucose", "blood glucose"]),
            ("HbA1c", ["hba1c", "hemoglobin a1c", "glycated hemoglobin", "a1c"]),
            ("Total Cholesterol", ["total cholesterol", "cholesterol, total", "cholesterol"]),
            ("LDL", ["ldl", "ldl-c", "ldl cholesterol", "low-density lipoprotein"]),
            ("HDL", ["hdl", "hdl-c", "hdl cholesterol", "high-density lipoprotein"]),
            ("Triglycerides", ["triglycerides", "trig"]),
            ("Creatinine", ["creatinine", "creat"]),
            ("Sodium", ["sodium", "na"]),
            ("Potassium", ["potassium", "k"]),
            ("Hemoglobin", ["hemoglobin", "hgb", "hb"]),
            ("TSH", ["tsh", "thyroid stimulating hormone"]),
            ("Vitamin D", ["vitamin d", "25-oh vitamin d", "25-hydroxyvitamin d"]),
            ("Vitamin B12", ["vitamin b12", "b12", "cobalamin"]),
            ("Ferritin", ["ferritin"])
        ]

        for line in lines {
            let lowerLine = line.lowercased()
            for pattern in patterns {
                guard !results.contains(where: { $0.name == pattern.name }) else { continue }
                guard pattern.aliases.contains(where: { lowerLine.contains($0) }) else { continue }

                let refRange = extractReferenceRange(from: line)
                let unit = extractUnit(from: line)
                // Strip the reference range from the line before looking for the
                // actual value, so "70-99" in a ref range doesn't get picked up
                // as "70". Same for lab IDs or headers parsed on the same row.
                let cleaned = stripNoise(from: line, referenceRange: refRange)
                guard let value = extractNumericValue(from: cleaned, unit: unit) else { continue }
                let isAbnormal = determineAbnormal(name: pattern.name.lowercased(), value: value)

                results.append(BloodBiomarker(
                    name: pattern.name,
                    value: value,
                    unit: unit,
                    referenceRange: refRange,
                    isAbnormal: isAbnormal
                ))
            }
        }

        return results
    }

    /// Remove the reference-range token from the line so it can't be mistaken
    /// for the actual value. Also collapses extra whitespace.
    private func stripNoise(from text: String, referenceRange: String) -> String {
        var cleaned = text
        if !referenceRange.isEmpty {
            cleaned = cleaned.replacingOccurrences(of: referenceRange, with: " ")
        }
        // Drop anything that looks like another lo-hi range we may have missed.
        if let regex = try? NSRegularExpression(pattern: #"[\d.]+\s*[-–]\s*[\d.]+"#) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: " ")
        }
        return cleaned
    }

    /// Pick the best candidate number for the biomarker value. If a unit is
    /// present we prefer the number that appears immediately before it (e.g.
    /// "92 mg/dL" → 92). Otherwise fall back to the first plausible number.
    private func extractNumericValue(from text: String, unit: String) -> Double? {
        if !unit.isEmpty {
            // Escape regex-significant chars in the unit (e.g. "mg/dL" has "/").
            let escaped = NSRegularExpression.escapedPattern(for: unit)
            let anchored = #"([\d]+\.?[\d]*)\s*"# + escaped
            if let regex = try? NSRegularExpression(pattern: anchored),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               match.numberOfRanges >= 2,
               let r = Range(match.range(at: 1), in: text),
               let v = Double(text[r]) {
                return v
            }
        }

        let pattern = #"[\d]+\.?[\d]*"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex?.matches(in: text, range: range) ?? []
        let numbers = matches.compactMap { match -> Double? in
            guard let range = Range(match.range, in: text) else { return nil }
            return Double(text[range])
        }
        return numbers.first(where: { $0 > 0 && $0 < 99999 })
    }

    private func extractUnit(from text: String) -> String {
        let unitPatterns = ["mg/dL", "mEq/L", "mmol/L", "g/dL", "ng/mL", "pg/mL", "mIU/L", "IU/L", "%", "g/L"]
        for unit in unitPatterns {
            if text.contains(unit) { return unit }
        }
        return ""
    }

    private func extractReferenceRange(from text: String) -> String {
        let pattern = #"[\d.]+\s*[-–]\s*[\d.]+"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        if let match = regex?.firstMatch(in: text, range: range),
           let r = Range(match.range, in: text) {
            return String(text[r])
        }
        return ""
    }

    private func extractDate(from text: String) -> Date? {
        let formats = ["MM/dd/yyyy", "MM-dd-yyyy", "yyyy-MM-dd", "MMMM dd, yyyy", "dd MMM yyyy"]
        let formatter = DateFormatter()
        let pattern = #"\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4}"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)

        if let match = regex?.firstMatch(in: text, range: range),
           let r = Range(match.range, in: text) {
            let dateStr = String(text[r])
            for format in formats {
                formatter.dateFormat = format
                if let date = formatter.date(from: dateStr) { return date }
            }
        }
        return nil
    }

    private func extractLabName(from text: String) -> String? {
        let knownLabs = ["Quest Diagnostics", "LabCorp", "Mayo Clinic", "Cleveland Clinic", "BioReference", "Sonora Quest"]
        for lab in knownLabs {
            if text.contains(lab) { return lab }
        }
        return nil
    }

    private func determineAbnormal(name: String, value: Double) -> Bool {
        guard let ref = BloodBiomarker.known[name] else { return false }
        return !ref.normalRange.contains(value)
    }
}

enum BloodTestError: Error {
    case cannotOpenPDF
    case noBiomarkersFound
}
