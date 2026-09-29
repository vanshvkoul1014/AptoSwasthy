import SwiftUI
import AVFoundation

struct FoodSearchView: View {
    let onAdd: (FoodEntry, MealType, Date) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var mode: SearchMode = .allFoods
    @State private var query = ""
    @State private var restaurantName = ""
    @State private var restaurantItem = ""
    @State private var results: [FoodSearchResult] = []
    @State private var isSearching = false
    @State private var error: String? = nil
    @State private var showScanner = false
    @State private var selectedMealType: MealType = MealType.fromHour(Calendar.current.component(.hour, from: Date()))
    @State private var mealTime: Date = Date()
    @State private var selectedResult: FoodSearchResult? = nil
    @State private var debounceTask: Task<Void, Never>? = nil

    enum SearchMode: String, CaseIterable, Identifiable {
        case allFoods = "All Foods"
        case restaurants = "Restaurant"
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            AnimatedGradientBackground()
            VStack(spacing: 0) {
                header
                mealContextBar
                modeToggle
                searchBar
                if let error {
                    Text(error)
                        .font(.pearlCaption)
                        .foregroundColor(.riskHigh)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                }
                resultsList
            }
        }
        .sheet(item: $selectedResult) { result in
            FoodPortionView(result: result) { entry in
                onAdd(entry, selectedMealType, mealTime)
                dismiss()
            }
        }
        .sheet(isPresented: $showScanner) {
            BarcodeScannerView { barcode in
                showScanner = false
                Task { await searchBarcode(barcode) }
            }
        }
        .presentationDetents([.large])
        .keyboardDismissable()
        .onChange(of: query) { _, _ in scheduleSearch() }
        .onChange(of: restaurantName) { _, _ in scheduleSearch() }
        .onChange(of: restaurantItem) { _, _ in scheduleSearch() }
        .onChange(of: mode) { _, _ in
            results = []
            scheduleSearch()
        }
    }

    // MARK: Subviews

    private var header: some View {
        HStack {
            Text("Add Food").font(.pearlTitle2).foregroundColor(.primaryText)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.quaternaryText)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    private var mealContextBar: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(MealType.allCases, id: \.self) { type in
                    Button(type.rawValue) { selectedMealType = type }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 11))
                    Text(selectedMealType.rawValue)
                        .font(.pearlCaption)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(.tertiaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassBackground(cornerRadius: 10)
            }

            DatePicker(
                "",
                selection: $mealTime,
                displayedComponents: [.hourAndMinute]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(.pearlGreen)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var modeToggle: some View {
        Picker("Mode", selection: $mode) {
            ForEach(SearchMode.allCases) { m in
                Text(m.rawValue).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var searchBar: some View {
        switch mode {
        case .allFoods:
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.quaternaryText)
                TextField("Search foods", text: $query)
                    .foregroundColor(.primaryText)
                    .submitLabel(.search)
                    .onSubmit { Task { await runAllFoodsSearch() } }
                if isSearching {
                    ProgressView().tint(.pearlGreen).scaleEffect(0.8)
                }
                Button { showScanner = true } label: {
                    Image(systemName: "barcode.viewfinder")
                        .foregroundColor(.pearlGreen)
                }
            }
            .padding(14)
            .glassBackground(cornerRadius: 14)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        case .restaurants:
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "storefront")
                        .foregroundColor(.quaternaryText)
                    TextField("Restaurant name (e.g. Chipotle)", text: $restaurantName)
                        .foregroundColor(.primaryText)
                        .submitLabel(.next)
                    if isSearching {
                        ProgressView().tint(.pearlGreen).scaleEffect(0.8)
                    }
                }
                .padding(14)
                .glassBackground(cornerRadius: 14)

                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(.quaternaryText)
                    TextField("Menu item (optional)", text: $restaurantItem)
                        .foregroundColor(.primaryText)
                        .submitLabel(.search)
                        .onSubmit { Task { await runRestaurantSearch() } }
                }
                .padding(14)
                .glassBackground(cornerRadius: 14)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if results.isEmpty && !isSearching {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(results) { result in
                        FoodResultRow(result: result) {
                            selectedResult = result
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: mode == .restaurants ? "storefront" : "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.quaternaryText)
            Text(mode == .restaurants
                 ? "Enter a restaurant and optionally a menu item."
                 : "Search for a food by name or scan a barcode.")
                .font(.pearlCaption)
                .foregroundColor(.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: Search plumbing

    private func scheduleSearch() {
        debounceTask?.cancel()
        debounceTask = Task { [mode] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            switch mode {
            case .allFoods:    await runAllFoodsSearch()
            case .restaurants: await runRestaurantSearch()
            }
        }
    }

    private func runAllFoodsSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }
        isSearching = true
        error = nil
        defer { isSearching = false }
        do {
            results = try await FoodDatabaseService.shared.search(query: trimmed)
        } catch FoodError.rateLimited {
            error = "Food search is temporarily rate limited. Try again in a minute."
        } catch {
            self.error = "Could not fetch results. Check your connection."
        }
    }

    private func runRestaurantSearch() async {
        let brand = restaurantName.trimmingCharacters(in: .whitespaces)
        let item = restaurantItem.trimmingCharacters(in: .whitespaces)
        guard brand.count >= 2 else { return }
        isSearching = true
        error = nil
        defer { isSearching = false }
        do {
            results = try await FoodDatabaseService.shared.searchRestaurant(
                brand: brand,
                item: item.isEmpty ? nil : item
            )
            if results.isEmpty {
                error = "No branded items found for \(brand)."
            }
        } catch FoodError.rateLimited {
            error = "Food search is temporarily rate limited. Try again in a minute."
        } catch {
            self.error = "Could not fetch results. Check your connection."
        }
    }

    private func searchBarcode(_ barcode: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            if let result = try await FoodDatabaseService.shared.lookupBarcode(barcode) {
                results = [result]
                query = result.name
            } else {
                error = "Barcode not found. Try searching manually."
            }
        } catch {
            self.error = "Barcode lookup failed."
        }
    }
}

// MARK: Result row

struct FoodResultRow: View {
    let result: FoodSearchResult
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.name)
                        .font(.pearlSubheadline)
                        .foregroundColor(.primaryText)
                        .multilineTextAlignment(.leading)
                    if let brand = result.brand {
                        Text(brand).font(.pearlCaption).foregroundColor(.tertiaryText)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(Int(result.calories)) kcal")
                        .font(.pearlSubheadline).foregroundColor(.primaryText)
                    Text("per \(formattedServing)")
                        .font(.pearlCaption2).foregroundColor(.quaternaryText)
                }
            }
            .padding(14)
            .glassBackground(cornerRadius: 14)
        }
    }

    private var formattedServing: String {
        let size = result.servingSize
        let unit = result.servingUnit
        if size == size.rounded() {
            return "\(Int(size)) \(unit)"
        }
        return String(format: "%.1f %@", size, unit)
    }
}

// MARK: Portion sheet

struct FoodPortionView: View {
    let result: FoodSearchResult
    let onConfirm: (FoodEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var quantity: Double = 1.0
    @State private var unit: FoodUnit

    init(result: FoodSearchResult, onConfirm: @escaping (FoodEntry) -> Void) {
        self.result = result
        self.onConfirm = onConfirm
        _unit = State(initialValue: FoodUnit.defaultForUSDA(unit: result.servingUnit))
    }

    private var factor: Double { result.macroFactor(quantity: quantity, unit: unit) }
    private var grams: Double { quantity * unit.gramsPerUnit(food: result) }

    var body: some View {
        ZStack {
            AnimatedGradientBackground()
            ScrollView {
                VStack(spacing: 20) {
                    header
                    portionEditor
                    macroCard
                    addButton
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }
        }
        .keyboardDismissable()
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(result.name)
                .font(.pearlTitle2)
                .foregroundColor(.primaryText)
                .multilineTextAlignment(.center)
            if let brand = result.brand {
                Text(brand)
                    .font(.pearlCaption)
                    .foregroundColor(.tertiaryText)
            }
        }
    }

    private var portionEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Portion")
                .font(.pearlFootnote.weight(.semibold))
                .tracking(0.8)
                .foregroundColor(.quaternaryText)
                .textCase(.uppercase)

            HStack(spacing: 14) {
                quantityStepper
                unitPicker
            }

            Text("Approximately \(gramsDisplay)")
                .font(.pearlCaption2)
                .foregroundColor(.quaternaryText)
        }
        .padding(18)
        .glassBackground(cornerRadius: 18)
    }

    private var quantityStepper: some View {
        HStack(spacing: 10) {
            Button {
                let step = quantityStep
                quantity = max(0.25, ((quantity - step) * 4).rounded() / 4)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(quantity > 0.25 ? .pearlGreen : .quaternaryText)
            }
            .disabled(quantity <= 0.25)

            TextField("", value: $quantity, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.pearlTitle3.weight(.semibold))
                .foregroundColor(.primaryText)
                .frame(minWidth: 60)
                .padding(.vertical, 10)
                .glassBackground(cornerRadius: 12)

            Button {
                let step = quantityStep
                quantity = ((quantity + step) * 4).rounded() / 4
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.pearlGreen)
            }
        }
    }

    private var unitPicker: some View {
        Menu {
            ForEach(FoodUnit.Category.allCases) { category in
                Section(category.rawValue) {
                    ForEach(unitsIn(category)) { u in
                        Button {
                            unit = u
                        } label: {
                            if u == unit {
                                Label(u.rawValue, systemImage: "checkmark")
                            } else {
                                Text(u.rawValue)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(unit.rawValue)
                    .font(.pearlCallout.weight(.semibold))
                    .foregroundColor(.primaryText)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.tertiaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .glassBackground(cornerRadius: 12)
        }
    }

    private var macroCard: some View {
        VStack(spacing: 8) {
            MacroRow(name: "Calories", value: Int((result.calories * factor).rounded()), unit: "kcal")
            MacroRow(name: "Protein",  value: Int((result.proteinG * factor).rounded()), unit: "g")
            MacroRow(name: "Carbs",    value: Int((result.carbsG * factor).rounded()),   unit: "g")
            MacroRow(name: "Fat",      value: Int((result.fatG * factor).rounded()),     unit: "g")
        }
        .padding(18)
        .glassBackground(cornerRadius: 18)
    }

    private var addButton: some View {
        Button {
            let entry = result.toFoodEntry(quantity: quantity, unit: unit)
            onConfirm(entry)
            dismiss()
        } label: {
            Text("Add to Meal")
                .font(.pearlHeadline)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var gramsDisplay: String {
        if grams >= 100 { return "\(Int(grams.rounded())) g" }
        return String(format: "%.1f g", grams)
    }

    /// Stepper increment chosen to match each unit's typical granularity. Cups
    /// go up in quarters, teaspoons in halves, grams in fives, etc.
    private var quantityStep: Double {
        switch unit {
        case .teaspoon, .tablespoon: return 0.5
        case .cup, .pint, .quart, .fluidOunce: return 0.25
        case .gram: return 5
        case .milliliter: return 10
        case .ounce, .liter: return 0.5
        case .pound, .kilogram: return 0.25
        default: return 0.5
        }
    }

    private func unitsIn(_ category: FoodUnit.Category) -> [FoodUnit] {
        FoodUnit.allCases.filter { $0.category == category }
    }
}
