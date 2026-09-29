import SwiftUI
import UniformTypeIdentifiers

struct BloodTestImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var importedTest: BloodTest? = nil
    @State private var editableBiomarkers: [BloodBiomarker] = []
    @State private var editingIndex: Int? = nil
    @State private var isProcessing = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            AnimatedGradientBackground()
            VStack(spacing: 24) {
                HStack {
                    Text("Import Blood Test").font(.pearlTitle2).foregroundColor(.primaryText)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 28)).foregroundColor(.quaternaryText)
                    }
                }
                .padding(.top, 24)

                if let test = importedTest {
                    // Results
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.riskLow)
                                Text("Import complete: \(editableBiomarkers.count) biomarkers found")
                                    .font(.pearlHeadline).foregroundColor(.primaryText)
                            }

                            if let lab = test.labName {
                                Text("Lab: \(lab)").font(.pearlSubheadline).foregroundColor(.tertiaryText)
                            }
                            if let date = test.testDate {
                                Text("Test date: \(date.formatted(date: .long, time: .omitted))")
                                    .font(.pearlSubheadline).foregroundColor(.tertiaryText)
                            }

                            Text("Tap any value to correct it before saving. Parsing is imperfect, and one wrong number will skew Pearl's models.")
                                .font(.pearlCaption).foregroundColor(.quaternaryText)
                                .fixedSize(horizontal: false, vertical: true)

                            ForEach(Array(editableBiomarkers.enumerated()), id: \.offset) { index, marker in
                                Button { editingIndex = index } label: {
                                    BiomarkerRow(marker: marker)
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                guard !editableBiomarkers.isEmpty else {
                                    errorMessage = "No biomarkers were found in this PDF. Make sure it's a standard lab report (not a scanned image)."
                                    return
                                }
                                test.biomarkers = editableBiomarkers
                                PersistenceService.shared.insert(test)
                                NotificationCenter.default.post(name: .bloodTestImported, object: nil)
                                dismiss()
                            } label: {
                                Text("Save & Update Pearl's Models")
                                    .font(.pearlHeadline).foregroundColor(.black)
                                    .frame(maxWidth: .infinity).frame(height: 56)
                                    .background(LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .leading, endPoint: .trailing))
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .padding(.top, 8)
                        }
                    }
                } else {
                    // Upload prompt
                    VStack(spacing: 20) {
                        Image(systemName: "doc.richtext.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .topLeading, endPoint: .bottomTrailing))

                        Text("Upload your blood test PDF")
                            .font(.pearlTitle2).foregroundColor(.primaryText)

                        Text("Pearl will read your biomarkers (cholesterol, glucose, HbA1c, vitamins, and more) and incorporate them into your life expectancy and risk models.")
                            .font(.pearlBody).foregroundColor(.tertiaryText)
                            .multilineTextAlignment(.center).lineSpacing(5)

                        if let error = errorMessage {
                            Text(error).font(.pearlSubheadline).foregroundColor(.riskHigh)
                        }

                        if isProcessing {
                            ProgressView("Reading your results...").tint(.pearlGreen).foregroundColor(.tertiaryText)
                        } else {
                            Button { showPicker = true } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.up.doc")
                                    Text("Choose PDF")
                                }
                                .font(.pearlHeadline).foregroundColor(.black)
                                .frame(maxWidth: .infinity).frame(height: 56)
                                .background(LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .leading, endPoint: .trailing))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                    .padding(.top, 20)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleImport(result) }
        }
        .sheet(item: Binding(
            get: { editingIndex.map { IndexBox(value: $0) } },
            set: { editingIndex = $0?.value }
        )) { box in
            if box.value < editableBiomarkers.count {
                BiomarkerEditSheet(marker: editableBiomarkers[box.value]) { updated in
                    editableBiomarkers[box.value] = updated
                    editingIndex = nil
                } onCancel: {
                    editingIndex = nil
                }
            }
        }
        .presentationDetents([.large])
    }

    private func handleImport(_ result: Result<[URL], Error>) async {
        await MainActor.run { isProcessing = true; errorMessage = nil }
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { throw BloodTestError.cannotOpenPDF }
            defer { url.stopAccessingSecurityScopedResource() }

            let test = try BloodTestImportService.shared.importPDF(at: url)
            await MainActor.run {
                importedTest = test
                editableBiomarkers = test.biomarkers
                isProcessing = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Couldn't read that PDF. Make sure it's a standard blood test report."
                isProcessing = false
            }
        }
    }
}

struct BiomarkerRow: View {
    let marker: BloodBiomarker

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(marker.name).font(.pearlSubheadline).foregroundColor(.primaryText)
                if !marker.referenceRange.isEmpty {
                    Text("Ref: \(marker.referenceRange) \(marker.unit)").font(.pearlCaption2).foregroundColor(.quaternaryText)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                Text("\(String(format: "%.1f", marker.value)) \(marker.unit)")
                    .font(.pearlSubheadline)
                    .foregroundColor(marker.isAbnormal ? .riskHigh : .white)
                if marker.isAbnormal {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.riskHigh)
                }
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundColor(.quaternaryText)
            }
        }
        .padding(12)
        .glassBackground(cornerRadius: 12)
    }
}

private struct IndexBox: Identifiable {
    let value: Int
    var id: Int { value }
}

private struct BiomarkerEditSheet: View {
    let marker: BloodBiomarker
    let onSave: (BloodBiomarker) -> Void
    let onCancel: () -> Void

    @State private var valueString: String = ""
    @State private var unit: String = ""
    @State private var referenceRange: String = ""

    var body: some View {
        ZStack {
            AnimatedGradientBackground()
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(marker.name).font(.pearlTitle2).foregroundColor(.primaryText)
                    Spacer()
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 28)).foregroundColor(.quaternaryText)
                    }
                }

                Text("Correct what the parser got wrong. Value is the most important. The reference range is just for context.")
                    .font(.pearlCaption).foregroundColor(.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 12) {
                    EditField(label: "Value", text: $valueString, keyboard: .decimalPad)
                    EditField(label: "Unit", text: $unit, keyboard: .default)
                    EditField(label: "Reference range", text: $referenceRange, keyboard: .default)
                }

                Spacer()

                Button {
                    guard let v = Double(valueString) else { onCancel(); return }
                    let name = marker.name.lowercased()
                    let isAbnormal: Bool = {
                        guard let ref = BloodBiomarker.known[name] else { return marker.isAbnormal }
                        return !ref.normalRange.contains(v)
                    }()
                    onSave(BloodBiomarker(
                        name: marker.name,
                        value: v,
                        unit: unit,
                        referenceRange: referenceRange,
                        isAbnormal: isAbnormal
                    ))
                } label: {
                    Text("Save")
                        .font(.pearlHeadline).foregroundColor(.black)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .leading, endPoint: .trailing))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(24)
        }
        .onAppear {
            valueString = String(format: "%g", marker.value)
            unit = marker.unit
            referenceRange = marker.referenceRange
        }
        .presentationDetents([.medium])
    }
}

private struct EditField: View {
    let label: String
    @Binding var text: String
    let keyboard: UIKeyboardType

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.pearlCaption).foregroundColor(.tertiaryText)
            TextField("", text: $text)
                .keyboardType(keyboard)
                .font(.pearlBody).foregroundColor(.primaryText)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .glassBackground(cornerRadius: 12)
        }
    }
}
