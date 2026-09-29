import Foundation

final class FoodDatabaseService: @unchecked Sendable {
    static let shared = FoodDatabaseService()

    // USDA FoodData Central API. DEMO_KEY is capped at ~30 req/hr per IP, which
    // is why search often failed with rateLimited. We now hit Open Food Facts
    // first (no key, no real rate limit) and fall back to USDA only if OFF
    // returns nothing.
    private let baseURL = "https://api.nal.usda.gov/fdc/v1"
    private let apiKey = "DEMO_KEY"

    // Open Food Facts (free, no API key).
    private let offSearchURL = "https://world.openfoodfacts.org/cgi/search.pl"
    private let offBarcodeURL = "https://world.openfoodfacts.org/api/v2/product"

    private init() {}

    func search(query: String) async throws -> [FoodSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Primary: Open Food Facts. Works globally, no key, no rate limits
        // that we hit in practice.
        if let offResults = try? await searchOpenFoodFacts(query: trimmed), !offResults.isEmpty {
            return Self.rankByRelevance(offResults, query: trimmed)
        }

        // Fallback: USDA. Keeps whole-food coverage (Foundation / SR Legacy)
        // that Open Food Facts doesn't carry.
        guard var components = URLComponents(string: "\(baseURL)/foods/search") else { throw FoodError.invalidURL }
        components.queryItems = [
            URLQueryItem(name: "query", value: trimmed),
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy,Branded"),
            URLQueryItem(name: "pageSize", value: "50"),
            URLQueryItem(name: "api_key", value: apiKey)
        ]
        guard let url = components.url else { throw FoodError.invalidURL }
        let data = try await fetchOK(url)
        let response = try JSONDecoder().decode(USDASearchResponse.self, from: data)
        let results = response.foods.map { FoodSearchResult(from: $0) }
        return Self.rankByRelevance(results, query: trimmed)
    }

    /// Restaurant-scoped search. Open Food Facts has a rich restaurant/brand
    /// dataset and a native `brands_tags` filter, so we use it as primary for
    /// this too. USDA Branded is kept as a secondary fallback.
    func searchRestaurant(brand: String, item: String? = nil) async throws -> [FoodSearchResult] {
        let brandTrimmed = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let itemTrimmed = item?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !brandTrimmed.isEmpty else { return [] }

        // Primary: Open Food Facts with brands filter.
        if let results = try? await searchOpenFoodFactsBrand(brand: brandTrimmed, item: itemTrimmed) {
            let searchPhrase = itemTrimmed.isEmpty ? brandTrimmed : itemTrimmed
            return boostByBrand(results, brand: brandTrimmed, searchPhrase: searchPhrase)
        }

        // Fallback: USDA Branded.
        guard var components = URLComponents(string: "\(baseURL)/foods/search") else { throw FoodError.invalidURL }
        let combinedQuery = [brandTrimmed, itemTrimmed]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        components.queryItems = [
            URLQueryItem(name: "query", value: combinedQuery),
            URLQueryItem(name: "dataType", value: "Branded"),
            URLQueryItem(name: "pageSize", value: "50"),
            URLQueryItem(name: "api_key", value: apiKey)
        ]
        guard let url = components.url else { throw FoodError.invalidURL }
        let data = try await fetchOK(url)
        let response = try JSONDecoder().decode(USDASearchResponse.self, from: data)
        let results = response.foods.map { FoodSearchResult(from: $0) }
        let searchPhrase = itemTrimmed.isEmpty ? brandTrimmed : itemTrimmed
        return boostByBrand(results, brand: brandTrimmed, searchPhrase: searchPhrase)
    }

    /// Apply a brand-match bonus on top of relevance score, so typing
    /// "Chipotle chicken" surfaces real Chipotle chicken above items that
    /// just happen to mention the brand name in their description.
    private func boostByBrand(_ results: [FoodSearchResult], brand: String, searchPhrase: String) -> [FoodSearchResult] {
        let brandLower = brand.lowercased()
        return results
            .map { result -> (FoodSearchResult, Int) in
                let b = (result.brand ?? "").lowercased()
                var brandScore = 0
                if b == brandLower { brandScore += 1000 }
                if !b.isEmpty, b.contains(brandLower) || brandLower.contains(b) { brandScore += 400 }
                return (result, brandScore + Self.relevanceScore(result, query: searchPhrase))
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    func lookup(fdcId: String) async throws -> FoodEntry {
        guard var components = URLComponents(string: "\(baseURL)/food/\(fdcId)") else { throw FoodError.invalidURL }
        components.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]

        guard let url = components.url else { throw FoodError.invalidURL }
        let data = try await fetchOK(url)
        let food = try JSONDecoder().decode(USDAFoodDetail.self, from: data)
        return food.toFoodEntry()
    }

    func lookupBarcode(_ barcode: String) async throws -> FoodSearchResult? {
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Primary: Open Food Facts (world leader in barcode coverage).
        if let result = try? await lookupOpenFoodFactsBarcode(trimmed) {
            return result
        }

        // Fallback: USDA Branded.
        guard var components = URLComponents(string: "\(baseURL)/foods/search") else { throw FoodError.invalidURL }
        components.queryItems = [
            URLQueryItem(name: "query", value: trimmed),
            URLQueryItem(name: "dataType", value: "Branded"),
            URLQueryItem(name: "pageSize", value: "1"),
            URLQueryItem(name: "api_key", value: apiKey)
        ]
        guard let url = components.url else { throw FoodError.invalidURL }
        let data = try await fetchOK(url)
        let response = try JSONDecoder().decode(USDASearchResponse.self, from: data)
        return response.foods.first.map { FoodSearchResult(from: $0) }
    }

    // MARK: - Open Food Facts

    private func searchOpenFoodFacts(query: String) async throws -> [FoodSearchResult] {
        guard var components = URLComponents(string: offSearchURL) else { throw FoodError.invalidURL }
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "50"),
            URLQueryItem(name: "fields", value: "code,product_name,brands,serving_size,serving_quantity,nutriments")
        ]
        guard let url = components.url else { throw FoodError.invalidURL }
        let data = try await fetchOK(url)
        let response = try JSONDecoder().decode(OFFSearchResponse.self, from: data)
        return response.products.compactMap { FoodSearchResult(from: $0) }
    }

    private func searchOpenFoodFactsBrand(brand: String, item: String) async throws -> [FoodSearchResult] {
        guard var components = URLComponents(string: offSearchURL) else { throw FoodError.invalidURL }
        var items: [URLQueryItem] = [
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "50"),
            URLQueryItem(name: "fields", value: "code,product_name,brands,serving_size,serving_quantity,nutriments"),
            URLQueryItem(name: "tagtype_0", value: "brands"),
            URLQueryItem(name: "tag_contains_0", value: "contains"),
            URLQueryItem(name: "tag_0", value: brand)
        ]
        if !item.isEmpty {
            items.append(URLQueryItem(name: "search_terms", value: item))
            items.append(URLQueryItem(name: "search_simple", value: "1"))
        }
        components.queryItems = items
        guard let url = components.url else { throw FoodError.invalidURL }
        let data = try await fetchOK(url)
        let response = try JSONDecoder().decode(OFFSearchResponse.self, from: data)
        return response.products.compactMap { FoodSearchResult(from: $0) }
    }

    private func lookupOpenFoodFactsBarcode(_ barcode: String) async throws -> FoodSearchResult? {
        guard let url = URL(string: "\(offBarcodeURL)/\(barcode).json?fields=code,product_name,brands,serving_size,serving_quantity,nutriments") else {
            throw FoodError.invalidURL
        }
        let data = try await fetchOK(url)
        let response = try JSONDecoder().decode(OFFProductResponse.self, from: data)
        guard response.status == 1, let product = response.product else { return nil }
        return FoodSearchResult(from: product)
    }

    /// Local relevance ordering for the USDA search payload. The API's native
    /// ranking tends to bubble generic Branded foods above simple whole foods,
    /// so we re-rank client-side with a conventional name-match score.
    static func rankByRelevance(_ results: [FoodSearchResult], query: String) -> [FoodSearchResult] {
        results.map { ($0, relevanceScore($0, query: query)) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    static func relevanceScore(_ result: FoodSearchResult, query: String) -> Int {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return 0 }
        let name = result.name.lowercased()
        var score = 0
        if name == q { score += 1000 }
        if name.hasPrefix(q) { score += 500 }
        if name.contains(q) { score += 200 }
        let tokens = name.split { !$0.isLetter && !$0.isNumber }.map { String($0) }
        for token in tokens {
            if token == q { score += 300 }
            else if token.hasPrefix(q) { score += 120 }
        }
        // Prefer whole foods (no brand) for short generic queries; prefer
        // branded items for multi-word queries that likely include a brand.
        if result.brand == nil { score += q.split(separator: " ").count <= 1 ? 80 : 0 }
        // Shorter names usually match the query more precisely.
        score -= min(name.count, 80) / 10
        return score
    }

    /// Fetch and assert a 2xx response. DEMO_KEY rate-limits (429) and invalid
    /// keys (403) return JSON error bodies the Decodable types do not match,
    /// which previously surfaced as generic decodingError. Now they surface
    /// as an explicit server or rate-limit status.
    private func fetchOK(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw FoodError.decodingError }
        switch http.statusCode {
        case 200...299: return data
        case 429:       throw FoodError.rateLimited
        case 404:       throw FoodError.notFound
        default:        throw FoodError.server(http.statusCode)
        }
    }
}

// MARK: - USDA API Models

struct USDASearchResponse: Decodable {
    let foods: [USDASearchFood]
}

struct USDASearchFood: Decodable {
    let fdcId: Int
    let description: String
    let brandName: String?
    let brandOwner: String?
    let servingSize: Double?
    let servingSizeUnit: String?
    let foodNutrients: [USDANutrientSummary]?
}

struct USDANutrientSummary: Decodable {
    let nutrientId: Int?
    let nutrientName: String?
    let value: Double?
    let unitName: String?
}

struct USDAFoodDetail: Decodable {
    let fdcId: Int
    let description: String
    let brandName: String?
    let servingSize: Double?
    let servingSizeUnit: String?
    let foodNutrients: [USDAFoodNutrient]?

    func toFoodEntry() -> FoodEntry {
        func nutrient(_ id: Int) -> Double {
            foodNutrients?.first { $0.nutrient?.id == id }?.amount ?? 0
        }
        return FoodEntry(
            foodName: description,
            brandName: brandName,
            servingSize: servingSize ?? 100,
            servingUnit: servingSizeUnit ?? "g",
            calories: nutrient(1008),
            proteinG: nutrient(1003),
            carbsG: nutrient(1005),
            fatG: nutrient(1004),
            fiberG: nutrient(1079),
            sugarG: nutrient(2000),
            sodiumMg: nutrient(1093),
            saturatedFatG: nutrient(1258),
            cholesterolMg: nutrient(1253),
            fdcId: String(fdcId)
        )
    }
}

struct USDAFoodNutrient: Decodable {
    let nutrient: USDANutrientRef?
    let amount: Double?
}

struct USDANutrientRef: Decodable {
    let id: Int?
    let name: String?
    let unitName: String?
}

struct FoodSearchResult: Identifiable {
    let id: String
    let fdcId: String
    let name: String
    let brand: String?
    let servingSize: Double
    let servingUnit: String
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    init(from food: USDASearchFood) {
        self.id = String(food.fdcId)
        self.fdcId = String(food.fdcId)
        self.name = food.description
        self.brand = food.brandName ?? food.brandOwner
        self.servingSize = food.servingSize ?? 100
        self.servingUnit = food.servingSizeUnit ?? "g"

        func nutrient(_ id: Int) -> Double {
            food.foodNutrients?.first { $0.nutrientId == id }?.value ?? 0
        }
        self.calories = nutrient(1008)
        self.proteinG = nutrient(1003)
        self.carbsG = nutrient(1005)
        self.fatG = nutrient(1004)
    }

    /// Build from an Open Food Facts product. OFF returns per-100 g nutriments
    /// under the `*_100g` keys, which matches our per-100 g convention
    /// elsewhere, so no rescaling needed. Returns nil when the product has
    /// no name or no calories, which would be unusable as a food entry.
    init?(from product: OFFProduct) {
        let trimmedName = (product.product_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        let energy = product.nutriments?.energyKcal100g ?? 0
        // Filter out records with literally no nutrition info, they create
        // rows that can't be logged meaningfully.
        if energy == 0,
           (product.nutriments?.proteins100g ?? 0) == 0,
           (product.nutriments?.carbohydrates100g ?? 0) == 0,
           (product.nutriments?.fat100g ?? 0) == 0 {
            return nil
        }

        self.id = product.code ?? UUID().uuidString
        self.fdcId = product.code ?? ""
        self.name = trimmedName
        let brand = (product.brands ?? "")
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.brand = (brand?.isEmpty == false) ? brand : nil
        // OFF stores per-100 g macros, so we anchor the reference portion at
        // 100 g. The portion sheet scales from there to whatever unit the
        // user picks.
        self.servingSize = 100
        self.servingUnit = "g"
        self.calories = energy
        self.proteinG = product.nutriments?.proteins100g ?? 0
        self.carbsG = product.nutriments?.carbohydrates100g ?? 0
        self.fatG = product.nutriments?.fat100g ?? 0
    }

    func toFoodEntry(servingMultiplier: Double = 1.0) -> FoodEntry {
        FoodEntry(
            foodName: name,
            brandName: brand,
            servingSize: servingSize * servingMultiplier,
            servingUnit: servingUnit,
            calories: calories * servingMultiplier,
            proteinG: proteinG * servingMultiplier,
            carbsG: carbsG * servingMultiplier,
            fatG: fatG * servingMultiplier,
            fdcId: fdcId
        )
    }

    /// Convert a chosen quantity (in `unit`) into a FoodEntry whose macros
    /// scale off the reference portion returned by USDA. Reference is
    /// (`servingSize` × `servingUnit`) and its macros are what's stored on
    /// this result. Example: a USDA Branded food with 150 g reference and
    /// 220 kcal; the user picks 1 cup (240 g), so factor is 240 ÷ 150.
    func toFoodEntry(quantity: Double, unit: FoodUnit) -> FoodEntry {
        let referenceGrams = FoodUnit.gramsForUSDA(value: servingSize, unit: servingUnit)
        let userGrams = quantity * unit.gramsPerUnit(food: self)
        let factor: Double = referenceGrams > 0 ? userGrams / referenceGrams : 1.0
        return FoodEntry(
            foodName: name,
            brandName: brand,
            servingSize: quantity,
            servingUnit: unit.rawValue,
            calories: calories * factor,
            proteinG: proteinG * factor,
            carbsG: carbsG * factor,
            fatG: fatG * factor,
            fdcId: fdcId
        )
    }

    /// Scaling factor the portion view applies to a single macro value when
    /// the user picks a (quantity, unit) pair. Live preview only.
    func macroFactor(quantity: Double, unit: FoodUnit) -> Double {
        let referenceGrams = FoodUnit.gramsForUSDA(value: servingSize, unit: servingUnit)
        let userGrams = quantity * unit.gramsPerUnit(food: self)
        return referenceGrams > 0 ? userGrams / referenceGrams : 1.0
    }
}

// MARK: - Open Food Facts models

/// Lossy decoding for the product list so a single malformed entry (OFF has
/// a long tail of half-entered records) doesn't invalidate the whole search.
struct OFFSearchResponse: Decodable {
    let products: [OFFProduct]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var unkeyed = try container.nestedUnkeyedContainer(forKey: .products)
        var out: [OFFProduct] = []
        while !unkeyed.isAtEnd {
            if let product = try? unkeyed.decode(OFFProduct.self) {
                out.append(product)
            } else {
                // Skip this element. An empty decodable advances the cursor.
                _ = try? unkeyed.decode(DropOne.self)
            }
        }
        self.products = out
    }

    private enum CodingKeys: String, CodingKey { case products }
    private struct DropOne: Decodable {}
}

struct OFFProductResponse: Decodable {
    let status: Int?
    let product: OFFProduct?
}

/// Open Food Facts sometimes returns `serving_quantity` as a number and
/// sometimes as a string (version drift across the API); decoding the whole
/// response fails if we pin it to one type. Since we anchor portions at 100 g
/// regardless, we simply don't decode it. Same story for `serving_size`,
/// which is free-form text and unused.
struct OFFProduct: Decodable {
    let code: String?
    let product_name: String?
    let brands: String?
    let nutriments: OFFNutriments?
}

/// Nutriments come back with hyphenated keys ("energy-kcal_100g"), which Swift
/// cannot express as property names, so we map them explicitly. Every field
/// is optional because Open Food Facts records vary widely in completeness.
struct OFFNutriments: Decodable {
    let energyKcal100g: Double?
    let proteins100g: Double?
    let carbohydrates100g: Double?
    let fat100g: Double?
    let fiber100g: Double?
    let sugars100g: Double?
    let sodium100g: Double?
    let saturatedFat100g: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g     = "energy-kcal_100g"
        case proteins100g       = "proteins_100g"
        case carbohydrates100g  = "carbohydrates_100g"
        case fat100g            = "fat_100g"
        case fiber100g          = "fiber_100g"
        case sugars100g         = "sugars_100g"
        case sodium100g         = "sodium_100g"
        case saturatedFat100g   = "saturated-fat_100g"
    }
}

/// Portion units the Add Food sheet offers. Each knows how many grams a single
/// unit represents (for mass and volume, an exact or near-water-density
/// conversion; for household portions, a tuned default that reads as
/// reasonable for most foods a user would log).
enum FoodUnit: String, CaseIterable, Identifiable, Codable {
    // Mass
    case gram = "g"
    case ounce = "oz"
    case pound = "lb"
    case kilogram = "kg"

    // Volume (metric)
    case milliliter = "ml"
    case liter = "L"

    // Volume (US household)
    case teaspoon = "tsp"
    case tablespoon = "tbsp"
    case fluidOunce = "fl oz"
    case cup = "cup"
    case pint = "pt"
    case quart = "qt"

    // Portion (household)
    case serving = "serving"
    case piece = "piece"
    case slice = "slice"
    case small = "small"
    case medium = "medium"
    case large = "large"
    case handful = "handful"
    case bowl = "bowl"
    case plate = "plate"
    case scoop = "scoop"
    case stick = "stick"
    case clove = "clove"
    case container = "container"
    case can = "can"
    case bottle = "bottle"

    var id: String { rawValue }

    enum Category: String, CaseIterable, Identifiable {
        case mass = "Mass"
        case volume = "Volume"
        case portion = "Portion"
        var id: String { rawValue }
    }

    var category: Category {
        switch self {
        case .gram, .ounce, .pound, .kilogram:
            return .mass
        case .milliliter, .liter, .teaspoon, .tablespoon, .fluidOunce, .cup, .pint, .quart:
            return .volume
        default:
            return .portion
        }
    }

    /// Grams represented by one of this unit, given the specific food for
    /// context. For household portion units (serving, slice, etc.) we look to
    /// the USDA reference portion first and fall back to a reasonable default.
    func gramsPerUnit(food: FoodSearchResult?) -> Double {
        switch self {
        case .gram:        return 1
        case .ounce:       return 28.3495
        case .pound:       return 453.592
        case .kilogram:    return 1000
        case .milliliter:  return 1
        case .liter:       return 1000
        case .teaspoon:    return 4.92892
        case .tablespoon:  return 14.7868
        case .fluidOunce:  return 29.5735
        case .cup:         return 240
        case .pint:        return 473.176
        case .quart:       return 946.353
        case .serving:
            if let f = food {
                let g = FoodUnit.gramsForUSDA(value: f.servingSize, unit: f.servingUnit)
                if g > 0 { return g }
            }
            return 100
        case .piece, .medium: return 100
        case .slice:         return 30
        case .small:         return 60
        case .large:         return 170
        case .handful:       return 30
        case .bowl:          return 250
        case .plate:         return 350
        case .scoop:         return 60
        case .stick:         return 113
        case .clove:         return 3
        case .container:     return 170
        case .can:           return 355
        case .bottle:        return 500
        }
    }

    /// Parse whatever `servingSizeUnit` string USDA returned into grams.
    /// Handles common variants ("GRM", "GRAM", "MLT", etc.) and falls back
    /// to assuming grams so we never divide by zero.
    static func gramsForUSDA(value: Double, unit: String) -> Double {
        let normalized = unit.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("g") { return value }
        if normalized.contains("kg") || normalized.contains("kilo") { return value * 1000 }
        if normalized.contains("lb") || normalized.contains("pound") { return value * 453.592 }
        if normalized.contains("oz") && !normalized.contains("fl") { return value * 28.3495 }
        if normalized.contains("mlt") || normalized == "ml" { return value }
        if normalized.contains("lit") { return value * 1000 }
        if normalized.contains("tsp") || normalized.contains("teaspoon") { return value * 4.92892 }
        if normalized.contains("tbsp") || normalized.contains("tablespoon") { return value * 14.7868 }
        if normalized.contains("fl oz") || normalized.contains("fluid ounce") { return value * 29.5735 }
        if normalized.contains("cup") { return value * 240 }
        if normalized.contains("pint") { return value * 473.176 }
        if normalized.contains("quart") { return value * 946.353 }
        if normalized.isEmpty { return value } // assume grams
        return value
    }

    /// The unit that best matches what USDA returned for this food, so the
    /// picker opens on something familiar instead of always defaulting to "g".
    static func defaultForUSDA(unit: String) -> FoodUnit {
        let normalized = unit.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("g") { return .gram }
        if normalized.contains("ml") { return .milliliter }
        if normalized.contains("cup") { return .cup }
        if normalized.contains("tbsp") { return .tablespoon }
        if normalized.contains("tsp") { return .teaspoon }
        if normalized.contains("fl oz") { return .fluidOunce }
        if normalized.contains("oz") { return .ounce }
        if normalized.contains("lb") { return .pound }
        return .serving
    }
}

enum FoodError: Error {
    case invalidURL
    case notFound
    case decodingError
    case rateLimited
    case server(Int)
}
