import SwiftUI

// MARK: - Name Step

struct NameStepView: View {
    @Binding var name: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Your name", text: $name)
            .textFieldStyle(GlassTextFieldStyle())
            .focused($focused)
            .textInputAutocapitalization(.words)
            .onAppear { focused = true }
    }
}

// MARK: - Date of Birth Step

struct DOBStepView: View {
    @Binding var dateOfBirth: Date

    var body: some View {
        DatePicker("Date of birth", selection: $dateOfBirth, in: ...Date(), displayedComponents: .date)
            .datePickerStyle(.wheel)
            .labelsHidden()
            .padding()
            .glassBackground(cornerRadius: 16)
    }
}

// MARK: - Biological Sex Step

struct BiologicalSexStepView: View {
    @Binding var biologicalSex: BiologicalSex

    var body: some View {
        VStack(spacing: 12) {
            ForEach(BiologicalSex.allCases, id: \.self) { sex in
                SelectionRow(
                    title: sex.rawValue,
                    isSelected: biologicalSex == sex
                ) { biologicalSex = sex }
            }
        }
    }
}

// MARK: - Ethnicity Step

struct EthnicityStepView: View {
    @Binding var ethnicity: Ethnicity

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Ethnicity.allCases, id: \.self) { eth in
                SelectionRow(
                    title: eth.rawValue,
                    isSelected: ethnicity == eth
                ) { ethnicity = eth }
            }
        }
    }
}

// MARK: - Height & Weight Step

struct HeightWeightStepView: View {
    @Binding var heightCm: Double
    @Binding var weightKg: Double
    @Binding var unitPreference: UnitSystem

    @State private var heightFeet: Double = 5
    @State private var heightInches: Double = 7
    @State private var weightLbs: Double = 154

    var body: some View {
        VStack(spacing: 20) {
            // Unit toggle
            Picker("Units", selection: $unitPreference) {
                ForEach(UnitSystem.allCases, id: \.self) { system in
                    Text(system == .imperial ? "Imperial" : "SI (Metric)").tag(system)
                }
            }
            .pickerStyle(.segmented)

            if unitPreference == .imperial {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Height")
                            .font(.pearlSubheadline).foregroundColor(.tertiaryText)
                        HStack(spacing: 16) {
                            SliderField(label: "ft", value: $heightFeet, range: 4...7, step: 1)
                            SliderField(label: "in", value: $heightInches, range: 0...11, step: 1)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Weight: \(Int(weightLbs)) lbs")
                            .font(.pearlSubheadline).foregroundColor(.tertiaryText)
                        Slider(value: $weightLbs, in: 80...400, step: 1)
                            .tint(.pearlGreen)
                    }
                }
                .onChange(of: heightFeet) { _, _ in updateCmFromImperial() }
                .onChange(of: heightInches) { _, _ in updateCmFromImperial() }
                .onChange(of: weightLbs) { _, v in weightKg = v / 2.20462 }
                .onAppear {
                    let totalInches = heightCm / 2.54
                    heightFeet = floor(totalInches / 12)
                    heightInches = totalInches.truncatingRemainder(dividingBy: 12)
                    weightLbs = weightKg * 2.20462
                }
            } else {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Height: \(Int(heightCm)) cm")
                            .font(.pearlSubheadline).foregroundColor(.tertiaryText)
                        Slider(value: $heightCm, in: 120...220, step: 1).tint(.pearlGreen)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Weight: \(Int(weightKg)) kg")
                            .font(.pearlSubheadline).foregroundColor(.tertiaryText)
                        Slider(value: $weightKg, in: 30...200, step: 0.5).tint(.pearlGreen)
                    }
                }
            }
        }
    }

    private func updateCmFromImperial() {
        heightCm = (heightFeet * 12 + heightInches) * 2.54
    }
}

struct SliderField: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        HStack {
            Text("\(Int(value)) \(label)")
                .font(.pearlHeadline).foregroundColor(.primaryText)
                .frame(width: 60)
            Slider(value: $value, in: range, step: step).tint(.pearlGreen)
        }
    }
}

// MARK: - Activity Level Step

struct ActivityLevelStepView: View {
    @Binding var activityLevel: ActivityLevel
    @Binding var minutesPerSession: Int

    var body: some View {
        VStack(spacing: 16) {
            ForEach(ActivityLevel.allCases, id: \.self) { level in
                SelectionRow(
                    title: level.rawValue,
                    isSelected: activityLevel == level
                ) { activityLevel = level }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Minutes per session: \(minutesPerSession) min")
                    .font(.pearlSubheadline).foregroundColor(.tertiaryText)
                Slider(value: Binding(
                    get: { Double(minutesPerSession) },
                    set: { minutesPerSession = Int($0) }
                ), in: 5...180, step: 5).tint(.pearlGreen)
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Sleep Schedule Step

struct SleepScheduleStepView: View {
    @Binding var bedtime: Date
    @Binding var wakeTime: Date
    @Binding var hours: Double

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bedtime").font(.pearlSubheadline).foregroundColor(.tertiaryText)
                    DatePicker("", selection: $bedtime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .padding(10).glassBackground(cornerRadius: 12)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Wake time").font(.pearlSubheadline).foregroundColor(.tertiaryText)
                    DatePicker("", selection: $wakeTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .padding(10).glassBackground(cornerRadius: 12)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Average hours: \(String(format: "%.1f", hours)) hrs")
                    .font(.pearlSubheadline).foregroundColor(.tertiaryText)
                Slider(value: $hours, in: 3...12, step: 0.5).tint(.pearlGreen)
            }
        }
    }
}

// MARK: - Health Conditions Step

private let commonConditions = [
    "None",
    // Cardiovascular
    "Hypertension", "High Cholesterol", "Cardiovascular Disease", "Coronary Artery Disease",
    "Heart Failure", "Atrial Fibrillation", "Arrhythmia", "Stroke (history)",
    "Peripheral Artery Disease", "Deep Vein Thrombosis", "Pulmonary Embolism",
    // Metabolic / endocrine
    "Type 1 Diabetes", "Type 2 Diabetes", "Prediabetes", "Gestational Diabetes",
    "Obesity", "Metabolic Syndrome", "Thyroid Disorder", "Hypothyroidism", "Hyperthyroidism",
    "PCOS", "Cushing's Syndrome", "Addison's Disease",
    // Respiratory
    "Asthma", "COPD", "Chronic Bronchitis", "Emphysema", "Sleep Apnea", "Pulmonary Hypertension",
    "Cystic Fibrosis", "Tuberculosis (history)",
    // Kidney / liver / GI
    "Chronic Kidney Disease", "Kidney Stones", "Liver Disease", "Fatty Liver Disease",
    "Hepatitis B", "Hepatitis C", "Cirrhosis",
    "GERD / Acid Reflux", "Irritable Bowel Syndrome", "Crohn's Disease", "Ulcerative Colitis",
    "Celiac Disease", "Gallstones", "Pancreatitis",
    // Neuro / mental health
    "Migraine", "Epilepsy", "Multiple Sclerosis", "Parkinson's Disease", "Alzheimer's / Dementia",
    "Neuropathy", "Chronic Pain", "Fibromyalgia",
    "Depression", "Anxiety", "Bipolar Disorder", "PTSD", "OCD", "ADHD", "Eating Disorder",
    "Substance Use Disorder",
    // Musculoskeletal / autoimmune
    "Osteoporosis", "Osteoarthritis", "Rheumatoid Arthritis", "Gout", "Lupus", "Psoriasis",
    "Psoriatic Arthritis", "Ankylosing Spondylitis", "Autoimmune Disease (other)",
    // Cancer
    "Cancer (any, active)", "Cancer (in remission)", "Breast Cancer", "Prostate Cancer",
    "Colorectal Cancer", "Lung Cancer", "Skin Cancer / Melanoma",
    // Infectious / immune
    "HIV / AIDS", "Chronic Fatigue Syndrome", "Long COVID",
    // Women's / reproductive
    "Endometriosis", "Uterine Fibroids", "Menopause", "Infertility",
    // Blood
    "Anemia", "Sickle Cell Disease", "Hemophilia", "Blood Clotting Disorder",
    // Other
    "Allergies (severe)", "Eczema", "Chronic Sinusitis", "Glaucoma", "Macular Degeneration",
    "Hearing Loss", "Tinnitus"
]

struct HealthConditionsStepView: View {
    @Binding var selected: Set<String>
    @State private var searchText = ""

    var filtered: [String] {
        searchText.isEmpty ? commonConditions : commonConditions.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 12) {
            TextField("Search conditions", text: $searchText)
                .textFieldStyle(GlassTextFieldStyle())

            FlowLayout(spacing: 10) {
                ForEach(filtered, id: \.self) { condition in
                    ChipButton(title: condition, isSelected: selected.contains(condition)) {
                        if condition == "None" {
                            selected = ["None"]
                        } else {
                            selected.remove("None")
                            if selected.contains(condition) { selected.remove(condition) }
                            else { selected.insert(condition) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Medications Step

private let commonMedications = [
    "None",
    // Cardiovascular / blood pressure
    "Lisinopril", "Enalapril", "Ramipril", "Losartan", "Valsartan", "Candesartan",
    "Amlodipine", "Nifedipine", "Diltiazem", "Verapamil",
    "Metoprolol", "Atenolol", "Carvedilol", "Bisoprolol", "Propranolol",
    "Hydrochlorothiazide", "Furosemide", "Spironolactone", "Chlorthalidone",
    // Cholesterol / lipids
    "Atorvastatin", "Rosuvastatin", "Simvastatin", "Pravastatin", "Ezetimibe",
    "Fenofibrate", "Gemfibrozil", "PCSK9 inhibitor",
    // Antiplatelet / anticoagulant
    "Aspirin (daily)", "Clopidogrel", "Warfarin", "Apixaban", "Rivaroxaban",
    "Dabigatran", "Heparin",
    // Diabetes
    "Metformin", "Insulin (long-acting)", "Insulin (rapid)", "Glipizide", "Glimepiride",
    "Sitagliptin", "Linagliptin", "Empagliflozin", "Dapagliflozin",
    "Semaglutide (Ozempic/Wegovy)", "Liraglutide", "Tirzepatide (Mounjaro/Zepbound)",
    "Pioglitazone",
    // Thyroid / endocrine
    "Levothyroxine", "Liothyronine", "Methimazole", "Propylthiouracil",
    "Prednisone", "Hydrocortisone",
    // GI / acid
    "Omeprazole", "Pantoprazole", "Esomeprazole", "Lansoprazole",
    "Ranitidine", "Famotidine", "Sucralfate", "Ondansetron", "Loperamide",
    // Respiratory
    "Albuterol inhaler", "Fluticasone inhaler", "Budesonide/Formoterol (Symbicort)",
    "Tiotropium (Spiriva)", "Montelukast (Singulair)", "Ipratropium",
    // Mental health - antidepressants
    "Sertraline (Zoloft)", "Escitalopram (Lexapro)", "Fluoxetine (Prozac)",
    "Citalopram", "Paroxetine", "Venlafaxine (Effexor)", "Duloxetine (Cymbalta)",
    "Bupropion (Wellbutrin)", "Mirtazapine", "Trazodone",
    // Mental health - other
    "Lithium", "Lamotrigine", "Quetiapine (Seroquel)", "Risperidone",
    "Olanzapine", "Aripiprazole", "Buspirone",
    // Anxiety / sleep
    "Alprazolam (Xanax)", "Lorazepam (Ativan)", "Clonazepam (Klonopin)",
    "Diazepam (Valium)", "Zolpidem (Ambien)", "Eszopiclone (Lunesta)",
    "Melatonin",
    // ADHD
    "Methylphenidate (Ritalin/Concerta)", "Amphetamine (Adderall)",
    "Lisdexamfetamine (Vyvanse)", "Atomoxetine (Strattera)",
    // Pain / neuropathy / inflammation
    "Acetaminophen / Tylenol", "Ibuprofen / Advil", "Naproxen / Aleve",
    "Gabapentin", "Pregabalin (Lyrica)", "Tramadol", "Oxycodone", "Hydrocodone",
    "Cyclobenzaprine", "Meloxicam", "Celecoxib",
    // Migraine
    "Sumatriptan", "Rizatriptan", "Topiramate", "Erenumab (Aimovig)",
    // Autoimmune / biologics
    "Methotrexate", "Hydroxychloroquine (Plaquenil)", "Sulfasalazine",
    "Adalimumab (Humira)", "Etanercept (Enbrel)", "Infliximab (Remicade)",
    "Rituximab", "Ustekinumab",
    // Bone / osteoporosis
    "Alendronate (Fosamax)", "Risedronate", "Denosumab (Prolia)",
    "Calcium supplement", "Vitamin D supplement",
    // Allergy
    "Cetirizine (Zyrtec)", "Loratadine (Claritin)", "Fexofenadine (Allegra)",
    "Diphenhydramine (Benadryl)", "Fluticasone nasal (Flonase)", "EpiPen",
    // Birth control / hormonal
    "Combined Oral Contraceptive", "Progestin-only Pill", "IUD (hormonal)",
    "IUD (copper)", "Estrogen (HRT)", "Progesterone (HRT)", "Testosterone",
    // Urology
    "Tamsulosin (Flomax)", "Finasteride", "Dutasteride", "Sildenafil (Viagra)",
    "Tadalafil (Cialis)",
    // Seizure
    "Levetiracetam (Keppra)", "Valproate", "Carbamazepine", "Phenytoin",
    // Parkinson's
    "Levodopa/Carbidopa (Sinemet)", "Pramipexole", "Ropinirole",
    // Dementia
    "Donepezil (Aricept)", "Rivastigmine", "Memantine",
    // Antibiotics / antivirals (chronic use)
    "Amoxicillin", "Azithromycin", "Doxycycline", "Ciprofloxacin",
    "Acyclovir", "Valacyclovir",
    // HIV
    "Bictegravir/Tenofovir/Emtricitabine (Biktarvy)", "Dolutegravir",
    "Emtricitabine/Tenofovir (Truvada)",
    // Supplements
    "Multivitamin", "Vitamin B12", "Iron supplement", "Magnesium",
    "Omega-3 / Fish oil", "Probiotic", "CoQ10", "Turmeric / Curcumin",
    "Other"
]

struct MedicationsStepView: View {
    @Binding var selected: Set<String>
    @State private var searchText = ""

    var filtered: [String] {
        searchText.isEmpty ? commonMedications : commonMedications.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Your medication data stays on this device and is never shared.")
                .font(.pearlCaption)
                .foregroundColor(.tertiaryText)
                .padding(.vertical, 4)

            TextField("Search medications", text: $searchText)
                .textFieldStyle(GlassTextFieldStyle())

            FlowLayout(spacing: 10) {
                ForEach(filtered, id: \.self) { med in
                    ChipButton(title: med, isSelected: selected.contains(med)) {
                        if med == "None" { selected = ["None"] }
                        else {
                            selected.remove("None")
                            if selected.contains(med) { selected.remove(med) } else { selected.insert(med) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Family History Step

private let familyConditions = [
    "Don't know", "None",
    "Heart Disease", "Heart Attack (early, <55M/<65F)", "Hypertension",
    "Stroke", "High Cholesterol", "Atrial Fibrillation",
    "Type 1 Diabetes", "Type 2 Diabetes", "Obesity",
    "Cancer (any)", "Breast Cancer", "Ovarian Cancer", "Colorectal Cancer",
    "Prostate Cancer", "Lung Cancer", "Pancreatic Cancer", "Skin Cancer / Melanoma",
    "Alzheimer's / Dementia", "Parkinson's Disease", "Huntington's Disease",
    "Multiple Sclerosis", "Epilepsy",
    "Depression", "Bipolar Disorder", "Schizophrenia", "Anxiety Disorder", "Suicide",
    "Kidney Disease", "Liver Disease",
    "Lung Disease / COPD", "Asthma",
    "Osteoporosis", "Rheumatoid Arthritis", "Lupus",
    "Thyroid Disorder", "Celiac Disease", "Inflammatory Bowel Disease",
    "Sickle Cell Disease", "Hemophilia", "Blood Clotting Disorder",
    "Cystic Fibrosis", "Muscular Dystrophy", "Genetic Disorder (other)",
    "Substance Use Disorder"
]

struct FamilyHistoryStepView: View {
    @Binding var selected: Set<String>

    var body: some View {
        FlowLayout(spacing: 10) {
            ForEach(familyConditions, id: \.self) { condition in
                ChipButton(title: condition, isSelected: selected.contains(condition)) {
                    if condition == "Don't know" { selected = ["Don't know"] }
                    else {
                        selected.remove("Don't know")
                        if selected.contains(condition) { selected.remove(condition) } else { selected.insert(condition) }
                    }
                }
            }
        }
    }
}

// MARK: - Smoking Step (status + pack-years + quit timing)

struct SmokingStepView: View {
    @Binding var smoking: SmokingStatus
    @Binding var packYears: Double
    @Binding var yearsSmoking: Int
    @Binding var yearsSinceQuit: Int
    @Binding var cigarettesPerDay: Int
    @Binding var vapes: Bool
    @Binding var secondhand: SecondhandSmokeLevel
    @Binding var cannabis: CannabisFrequency

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Current status").font(.pearlHeadline).foregroundColor(.primaryText)
                ForEach(SmokingStatus.allCases, id: \.self) { status in
                    SelectionRow(title: status.rawValue, isSelected: smoking == status) { smoking = status }
                }
            }

            if smoking == .current {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cigarettes per day: \(cigarettesPerDay)")
                        .font(.pearlSubheadline).foregroundColor(.tertiaryText)
                    Slider(value: Binding(
                        get: { Double(cigarettesPerDay) },
                        set: { cigarettesPerDay = Int($0) }
                    ), in: 0...60, step: 1).tint(.pearlGreen)
                }
                .transition(.opacity)
            }

            if smoking != .never {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Years as a smoker: \(yearsSmoking)")
                        .font(.pearlSubheadline).foregroundColor(.tertiaryText)
                    Slider(value: Binding(
                        get: { Double(yearsSmoking) },
                        set: { yearsSmoking = Int($0) }
                    ), in: 0...60, step: 1).tint(.pearlGreen)

                    Text("Pack-years (packs/day × years): \(String(format: "%.1f", packYears))")
                        .font(.pearlSubheadline).foregroundColor(.tertiaryText)
                    Slider(value: $packYears, in: 0...80, step: 0.5).tint(.pearlGreen)
                    Text("E.g. 1 pack/day for 20 years = 20 pack-years.")
                        .font(.pearlCaption).foregroundColor(.quaternaryText)
                }
                .transition(.opacity)
            }

            if smoking == .former {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Years since quitting: \(yearsSinceQuit)")
                        .font(.pearlSubheadline).foregroundColor(.tertiaryText)
                    Slider(value: Binding(
                        get: { Double(yearsSinceQuit) },
                        set: { yearsSinceQuit = Int($0) }
                    ), in: 0...50, step: 1).tint(.pearlGreen)
                }
                .transition(.opacity)
            }

            Toggle("I vape or use e-cigarettes", isOn: $vapes)
                .font(.pearlSubheadline)
                .foregroundColor(.primaryText)
                .tint(.pearlGreen)

            VStack(alignment: .leading, spacing: 10) {
                Text("Secondhand smoke exposure").font(.pearlHeadline).foregroundColor(.primaryText)
                ForEach(SecondhandSmokeLevel.allCases, id: \.self) { lvl in
                    SelectionRow(title: lvl.displayName, isSelected: secondhand == lvl) { secondhand = lvl }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Cannabis use").font(.pearlHeadline).foregroundColor(.primaryText)
                ForEach(CannabisFrequency.allCases, id: \.self) { f in
                    SelectionRow(title: f.rawValue, isSelected: cannabis == f) { cannabis = f }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: smoking)
    }
}

// MARK: - Alcohol Step (frequency + drinks per week)

struct AlcoholStepView: View {
    @Binding var alcohol: AlcoholFrequency
    @Binding var drinksPerWeek: Int
    @Binding var bingeFrequency: BingeFrequency
    @Binding var alcoholFreeDays: Int
    @Binding var beverageTypes: [String]

    private let beverages = ["Beer", "Wine", "Spirits / liquor", "Cocktails", "Seltzer / RTD"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("How often?").font(.pearlHeadline).foregroundColor(.primaryText)
                ForEach(AlcoholFrequency.allCases, id: \.self) { freq in
                    SelectionRow(title: freq.rawValue, isSelected: alcohol == freq) { alcohol = freq }
                }
            }

            if alcohol != .never {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Drinks per week: \(drinksPerWeek)")
                        .font(.pearlSubheadline).foregroundColor(.tertiaryText)
                    Slider(value: Binding(
                        get: { Double(drinksPerWeek) },
                        set: { drinksPerWeek = Int($0) }
                    ), in: 0...40, step: 1).tint(.pearlGreen)
                    Text("One standard drink ≈ 12 oz beer, 5 oz wine, or 1.5 oz spirits.")
                        .font(.pearlCaption).foregroundColor(.quaternaryText)
                }
                .transition(.opacity)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Alcohol-free days per week: \(alcoholFreeDays)")
                        .font(.pearlSubheadline).foregroundColor(.tertiaryText)
                    Slider(value: Binding(
                        get: { Double(alcoholFreeDays) },
                        set: { alcoholFreeDays = Int($0) }
                    ), in: 0...7, step: 1).tint(.pearlGreen)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Binge-level sessions").font(.pearlHeadline).foregroundColor(.primaryText)
                    Text("A binge = 4+ drinks (women) or 5+ drinks (men) inside ~2 hours.")
                        .font(.pearlCaption).foregroundColor(.quaternaryText)
                    ForEach(BingeFrequency.allCases, id: \.self) { f in
                        SelectionRow(title: f.rawValue, isSelected: bingeFrequency == f) { bingeFrequency = f }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("What you typically drink").font(.pearlHeadline).foregroundColor(.primaryText)
                    FlowLayout(spacing: 8) {
                        ForEach(beverages, id: \.self) { b in
                            ChipButton(title: b, isSelected: beverageTypes.contains(b)) {
                                if beverageTypes.contains(b) {
                                    beverageTypes.removeAll { $0 == b }
                                } else {
                                    beverageTypes.append(b)
                                }
                            }
                        }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: alcohol)
    }
}

// MARK: - Eating Habits Step

struct EatingHabitsStepView: View {
    @Binding var dietType: DietType
    @Binding var mealsPerDay: Int
    @Binding var fastFoodPerWeek: Int
    @Binding var waterGlassesPerDay: Int
    @Binding var caffeineCupsPerDay: Int
    @Binding var addedSugarServingsPerDay: Int
    @Binding var vegetableServings: Int
    @Binding var fruitServings: Int
    @Binding var homeCookedPerWeek: Int
    @Binding var lateNightPerWeek: Int
    @Binding var eatingWindowHours: Int
    @Binding var processedFoodFrequency: ProcessedFoodFrequency
    @Binding var emotionalEating: EmotionalEatingFrequency
    @Binding var proteinSources: [String]

    private let proteinOptions = ["Red meat", "Poultry", "Fish / seafood", "Eggs", "Dairy", "Legumes / beans", "Tofu / tempeh", "Nuts / seeds", "Protein powder"]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Primary eating pattern")
                    .font(.pearlHeadline).foregroundColor(.primaryText)
                Menu {
                    ForEach(DietType.allCases, id: \.self) { d in
                        Button(d.rawValue) { dietType = d }
                    }
                } label: {
                    HStack {
                        Text(dietType.rawValue)
                            .font(.pearlCallout).foregroundColor(.primaryText)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundColor(.tertiaryText)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(Color.glassBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.glassBorder, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            CountSliderRow(title: "Meals per day",       value: $mealsPerDay, range: 1...8,  caption: "Include substantial snacks.")
            CountSliderRow(title: "Daily eating window (hours)", value: $eatingWindowHours, range: 4...24, caption: "Time between first and last food of the day. 8 = intermittent fasting.")
            CountSliderRow(title: "Home-cooked meals per week", value: $homeCookedPerWeek, range: 0...21, caption: nil)
            CountSliderRow(title: "Fast food / takeout per week", value: $fastFoodPerWeek, range: 0...20, caption: nil)
            CountSliderRow(title: "Vegetable servings per day", value: $vegetableServings, range: 0...10, caption: "~½ cup cooked or 1 cup raw each.")
            CountSliderRow(title: "Fruit servings per day", value: $fruitServings, range: 0...10, caption: nil)
            CountSliderRow(title: "Glasses of water per day (~8oz)", value: $waterGlassesPerDay, range: 0...20, caption: nil)
            CountSliderRow(title: "Caffeinated drinks per day", value: $caffeineCupsPerDay, range: 0...10, caption: "Coffee, tea, energy drinks.")
            CountSliderRow(title: "Added sugar servings per day", value: $addedSugarServingsPerDay, range: 0...20, caption: "Soda, desserts, sweetened coffee.")
            CountSliderRow(title: "Late-night eating (times / week)", value: $lateNightPerWeek, range: 0...14, caption: "Eating within 3 hours of bedtime.")

            VStack(alignment: .leading, spacing: 10) {
                Text("Ultra-processed food frequency")
                    .font(.pearlHeadline).foregroundColor(.primaryText)
                ForEach(ProcessedFoodFrequency.allCases, id: \.self) { f in
                    SelectionRow(title: f.rawValue, isSelected: processedFoodFrequency == f) { processedFoodFrequency = f }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Emotional / stress eating")
                    .font(.pearlHeadline).foregroundColor(.primaryText)
                ForEach(EmotionalEatingFrequency.allCases, id: \.self) { f in
                    SelectionRow(title: f.rawValue, isSelected: emotionalEating == f) { emotionalEating = f }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Main protein sources").font(.pearlHeadline).foregroundColor(.primaryText)
                FlowLayout(spacing: 8) {
                    ForEach(proteinOptions, id: \.self) { p in
                        ChipButton(title: p, isSelected: proteinSources.contains(p)) {
                            if proteinSources.contains(p) {
                                proteinSources.removeAll { $0 == p }
                            } else {
                                proteinSources.append(p)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct CountSliderRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title): \(value)")
                .font(.pearlSubheadline).foregroundColor(.tertiaryText)
            Slider(value: Binding(
                get: { Double(value) },
                set: { value = Int($0) }
            ), in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
            .tint(.pearlGreen)
            if let caption {
                Text(caption).font(.pearlCaption).foregroundColor(.quaternaryText)
            }
        }
    }
}

// MARK: - Exercise Types Step

struct ExerciseTypesStepView: View {
    @Binding var selected: Set<ExerciseType>

    var body: some View {
        FlowLayout(spacing: 10) {
            ForEach(ExerciseType.allCases, id: \.self) { type in
                ChipButton(title: type.rawValue, isSelected: selected.contains(type)) {
                    if type == .none {
                        selected = [.none]
                    } else {
                        selected.remove(.none)
                        if selected.contains(type) { selected.remove(type) } else { selected.insert(type) }
                    }
                }
            }
        }
    }
}

// MARK: - Stress & Screen Time Step

struct StressScreenTimeStepView: View {
    @Binding var stressLevel: Int
    @Binding var screenTimeHours: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Typical stress level: \(stressLevel)/10")
                    .font(.pearlSubheadline).foregroundColor(.tertiaryText)
                Slider(value: Binding(
                    get: { Double(stressLevel) },
                    set: { stressLevel = Int($0) }
                ), in: 1...10, step: 1).tint(.pearlGreen)
                Text("1 = very calm, 10 = overwhelmed")
                    .font(.pearlCaption).foregroundColor(.quaternaryText)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Recreational screen time: \(String(format: "%.1f", screenTimeHours)) hrs/day")
                    .font(.pearlSubheadline).foregroundColor(.tertiaryText)
                Slider(value: $screenTimeHours, in: 0...16, step: 0.5).tint(.pearlGreen)
                Text("Phone, TV, and social media. Work screens are excluded.")
                    .font(.pearlCaption).foregroundColor(.quaternaryText)
            }
        }
    }
}

// MARK: - Biography Step (free-text)

struct BiographyStepView: View {
    @Binding var note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Anything Pearl should keep in mind. Recent life changes, symptoms you're tracking, or goals in your own words.")
                .font(.pearlCaption).foregroundColor(.tertiaryText)

            TextEditor(text: $note)
                .font(.pearlBody)
                .foregroundColor(.primaryText)
                .frame(minHeight: 160)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(Color.glassBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.glassBorder, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: - Sleep Quality (added as subcomponent in sleep step)

struct SleepQualityRow: View {
    @Binding var quality: SleepQuality

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How would you rate your sleep quality?")
                .font(.pearlSubheadline).foregroundColor(.tertiaryText)
            ForEach(SleepQuality.allCases, id: \.self) { q in
                SelectionRow(title: q.displayName, isSelected: quality == q) { quality = q }
            }
        }
    }
}

// MARK: - Health Goals Step

struct HealthGoalsStepView: View {
    @Binding var selected: Set<HealthGoal>

    var body: some View {
        VStack(spacing: 12) {
            ForEach(HealthGoal.allCases, id: \.self) { goal in
                SelectionRow(
                    title: goal.rawValue,
                    isSelected: selected.contains(goal),
                    multiSelect: true
                ) {
                    if selected.contains(goal) { selected.remove(goal) } else { selected.insert(goal) }
                }
            }
        }
    }
}

// MARK: - Shared Components

struct SelectionRow: View {
    let title: String
    let isSelected: Bool
    var multiSelect: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.pearlCallout)
                    .foregroundColor(.primaryText)
                Spacer()
                if isSelected {
                    Image(systemName: multiSelect ? "checkmark.square.fill" : "checkmark.circle.fill")
                        .foregroundColor(.pearlGreen)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? Color.pearlGreen.opacity(0.15) : Color.glassBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.pearlGreen.opacity(0.5) : Color.glassBorder, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

struct ChipButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.pearlCaption)
                .foregroundColor(isSelected ? .white : .primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.pearlGreen : Color.glassBackground)
                .overlay {
                    Capsule()
                        .strokeBorder(isSelected ? Color.pearlGreen : Color.glassBorder, lineWidth: 1)
                }
                .clipShape(Capsule())
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0

        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                y += rowH + spacing; x = 0; rowH = 0
            }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0

        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowH + spacing; x = bounds.minX; rowH = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
