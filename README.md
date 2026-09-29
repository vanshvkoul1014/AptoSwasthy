# AptoSwasthy: Your Personal Health Intelligence App

AptoSwasthy is an iOS app that acts like a personal health advisor in your pocket. It tracks your health metrics, analyzes your habits, estimates your life expectancy, and gives you personalized recommendations — all powered by an AI assistant called **Pearl**.

Think of it as your smart health dashboard: connect it to Apple Health, log your meals, import blood test results, and Pearl will make sense of it all for you.

> **Project Note:** AptoSwasthy was co-developed as a collaborative project. This repository contains the application and backend implementation used in my portfolio, including my contributions to the iOS app, health intelligence features, backend integration, and supporting functionality.

---

## What the App Does

- **Health Dashboard** — See all your key health stats (heart rate, steps, sleep, blood pressure, weight, and more) in one place
- **Pearl AI Chat** — Ask Pearl questions about your health and get personalized, data-driven answers
- **Life Expectancy Estimate** — See a running estimate of your lifespan based on your health data, along with factors that may help or hurt it
- **Disease Risk Assessment** — Get a breakdown of risk factors for common conditions based on your profile and metrics
- **Nutrition Logger** — Log meals by searching foods or scanning barcodes and view your nutrition score
- **Habit Tracker** — Receive personalized health-habit recommendations and track progress
- **3D Body Visualization** — View a body model that reflects your height, weight, and body composition
- **Blood Test Import** — Upload lab results for structured analysis
- **Apple Health Sync** — Pull supported health data from Apple Health

---

## Tech Stack

- **iOS:** Swift, SwiftUI, SwiftData
- **Health Data:** HealthKit
- **AI:** Apple FoundationModels with typed tools and a fallback Pearl implementation
- **Authentication:** Amazon Cognito, OAuth
- **Backend:** AWS API Gateway, Lambda, DynamoDB
- **Security:** Keychain-backed token storage
- **Documents:** PDFKit
- **Visualization:** SceneKit / ModelIO with a CAESAR-derived parametric body model
- **Infrastructure:** AWS SAM
- **Project Generation:** XcodeGen

---

## Compatibility

- **Core app:** iOS 18+
- **Pearl with Apple FoundationModels:** iOS 26+ on supported Apple Intelligence devices
- **Fallback Pearl implementation:** used when FoundationModels is unavailable
- **Development environment:** macOS 14 (Sonoma) or newer with Xcode 16+

---

## What You'll Need Before Starting

You need a **Mac computer** to build and run this app.

| What | Why | Free? |
|------|-----|-------|
| A Mac running macOS 14 (Sonoma) or newer | Required to run Xcode | Yes |
| **Xcode 16** or newer | Apple's tool for building iOS apps | Yes |
| An Apple ID | Required to run the app on a physical iPhone | Yes |
| An iPhone running **iOS 18** or newer | Optional for device testing; the simulator also works | Varies |
| **Homebrew** | Package manager for developer tools | Yes |
| **XcodeGen** | Generates the Xcode project from `project.yml` | Yes |
| **CAESAR Body Model Data** | Only required if rebuilding the 3D model binary | Free registration required |

---

## Starting on a New Computer — Quick Start

### 1. Install Xcode

Open the **App Store**, search for **Xcode**, and install it. Open Xcode once after installation so it can finish setup and accept the license agreement.

### 2. Clone the Repository

Open **Terminal** and run:

```bash
cd ~/Desktop
git clone https://github.com/vanshvkoul1014/AptoSwasthy.git
cd AptoSwasthy
```

If macOS prompts you to install the Xcode Command Line Tools, complete that installation and rerun the clone command.

If you received the project as a ZIP instead, extract it and keep the folder name as `AptoSwasthy`, then navigate to that folder in Terminal.

### 3. Run the Setup Script

From the repository root:

```bash
./setup.sh
```

The script:

- verifies you are on macOS
- checks for Xcode Command Line Tools
- installs Homebrew if needed
- installs dependencies from the `Brewfile`
- runs XcodeGen
- opens the generated Xcode project

### 4. Select Your Development Team and Run

When Xcode opens:

1. Click **AptoSwasthy** in the left sidebar
2. Open **Signing & Capabilities**
3. Select your Apple ID under **Team**
4. Choose an iPhone simulator or connected iPhone
5. Press **Run** (`⌘ + R`)

> The core app runs on iOS 18+. The Apple FoundationModels version of Pearl requires iOS 26+ and supported Apple Intelligence hardware.

---

## Step-by-Step Setup Guide

Use this section if the setup script does not work or if you want to configure the project manually.

### Step 1 — Install Xcode

Install **Xcode 16 or newer** from the Mac App Store and open it once after installation.

### Step 2 — Install Homebrew

Run:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Follow the terminal prompts.

### Step 3 — Install XcodeGen

```bash
brew install xcodegen
```

### Step 4 — Download the App Code

Clone the repository:

```bash
git clone https://github.com/vanshvkoul1014/AptoSwasthy.git
```

Then enter the repository:

```bash
cd AptoSwasthy
```

### Step 5 — Generate the Xcode Project

The XcodeGen configuration is inside the nested iOS project directory:

```bash
cd AptoSwasthy
xcodegen generate
```

If the repository is located on your Desktop, the full path would be:

```bash
cd ~/Desktop/AptoSwasthy/AptoSwasthy
xcodegen generate
```

You should see output indicating that `AptoSwasthy.xcodeproj` was generated.

### Step 6 — Open the Project

```bash
open AptoSwasthy.xcodeproj
```

### Step 7 — Configure Signing

1. Click **AptoSwasthy** in Xcode's project navigator
2. Open **Signing & Capabilities**
3. Select your Apple ID under **Team**

### Step 8 — Run the App

Choose a simulator or connected iPhone and press:

```text
⌘ + R
```

---

## First Time Using the App

When you first open AptoSwasthy:

1. **Create an account** and verify your email
2. **Grant permissions** for supported Apple Health data and optional app features
3. **Complete onboarding** so Pearl can use your profile when generating insights
4. **Explore the dashboard**, nutrition logger, habits, risk assessment, body model, and Pearl

---

## Pearl

Pearl is AptoSwasthy's health intelligence assistant.

On supported devices, Pearl uses Apple's **FoundationModels** framework and typed tools so that structured values such as metrics, trends, disease-risk calculations, nutrition data, habits, and life-expectancy factors come from app logic rather than being invented by the language model.

When FoundationModels is unavailable, the app can fall back to its non-FoundationModels Pearl implementation.

Key capabilities include:

- current health metric lookup
- metric trends and history
- disease-risk assessment
- life-expectancy factor analysis
- nutrition summaries
- habit recommendations
- blood-test summaries and biomarker trends
- baseline and period comparisons
- metric logging through typed tools

---

## Health Data and Persistence

AptoSwasthy integrates with **HealthKit** to read supported health metrics such as:

- heart rate
- resting heart rate
- heart-rate variability
- steps
- sleep
- blood oxygen
- respiratory rate
- active energy
- exercise minutes
- weight and body composition
- additional supported metrics

Local application data is persisted using **SwiftData**.

Authentication tokens are stored using the **iOS Keychain**.

---

## AWS Backend

The project includes a serverless AWS backend for authenticated profile synchronization.

The infrastructure includes:

- **Amazon Cognito** for authentication
- **API Gateway** for HTTP endpoints
- **AWS Lambda** for backend logic
- **DynamoDB** for profile persistence
- **AWS SAM** for infrastructure configuration

Backend infrastructure is located in:

```text
AptoSwasthy/infra/
```

Deployment-specific configuration is intentionally kept separate from secrets. Do not commit AWS access keys, private keys, `.env` files, or other credentials.

---

## Blood Test Import

AptoSwasthy supports importing blood-test documents with **PDFKit**.

Imported biomarkers can be stored in the app and used by Pearl for:

- latest blood-panel summaries
- abnormal-value flags
- biomarker history
- biomarker trend analysis

---

## 3D Body Model

AptoSwasthy includes a parametric 3D body visualization based on the **CAESAR / HumanShape** anthropometric dataset.

The repository already includes the preprocessed:

```text
body_basis.bin
```

so the body model works without downloading the raw CAESAR files.

You only need the original dataset if you want to rebuild the binary.

### Raw Dataset Files

The conversion workflow expects:

| File | Approx. Size | Purpose |
|------|-------------:|---------|
| `meanShape.mat` | ~1 MB | Mean human body mesh |
| `evalues.mat` | ~1 MB | Shape-component variance |
| `evectors.mat` | ~610 MB | Shape variation vectors |
| `model.dat` | ~1 MB | Mesh triangle structure |

The raw dataset is not committed to this repository.

### Dataset Location

If rebuilding the model, place the raw files in:

```text
AptoSwasthy/
└── caesar-norm-wsx/
    ├── meanShape.mat
    ├── evalues.mat
    ├── evectors.mat
    └── model.dat
```

### Rebuild the Binary

Install the Python dependencies:

```bash
pip3 install numpy scipy
```

From the repository root, run:

```bash
python3 AptoSwasthy/tools/convert_humanshape.py
```

The conversion script regenerates the app's `body_basis.bin`.

> The raw `caesar-norm-wsx/` directory is excluded from Git because the dataset is large and distributed separately under its own licensing terms.

---

## Project Structure

```text
AptoSwasthy/
├── AptoSwasthy/
│   ├── Sources/
│   │   └── AptoSwasthy/
│   │       ├── AI/
│   │       ├── App/
│   │       ├── Authentication/
│   │       ├── Design/
│   │       ├── Home/
│   │       ├── Models/
│   │       ├── Onboarding/
│   │       ├── Pearl/
│   │       ├── Resources/
│   │       ├── Risks/
│   │       ├── Services/
│   │       └── You/
│   ├── infra/
│   │   ├── profile/
│   │   ├── README.md
│   │   └── template.yaml
│   ├── tools/
│   │   └── convert_humanshape.py
│   ├── project.yml
│   └── AptoSwasthy.xcodeproj/
├── Brewfile
├── setup.sh
├── appicon.png
├── .gitignore
└── README.md
```

---

## Troubleshooting

### "No such module" or project-generation issues

Run XcodeGen from:

```bash
cd AptoSwasthy
xcodegen generate
```

### Signing certificate error

In Xcode, go to **Signing & Capabilities** and select your Apple ID under **Team**.

### App does not run on the selected device

Make sure the device or simulator is running **iOS 18 or newer**.

### FoundationModels version of Pearl is unavailable

Apple FoundationModels requires **iOS 26+** and compatible Apple Intelligence hardware. On unsupported environments, use the app's fallback Pearl implementation.

### Build fails because Xcode is too old

Use **Xcode 16 or newer** for the core project. Newer SDK availability may be required when compiling FoundationModels functionality.

---

## Contributors

- **Vansh Koul**
- **Rohan Gandotra**

---

## Disclaimer

AptoSwasthy is a software project intended for health-data organization, experimentation, and informational insights. It is not a substitute for professional medical diagnosis or treatment.
