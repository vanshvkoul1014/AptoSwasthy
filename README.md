# AptoSwasthy: Your Personal Health Intelligence App

AptoSwasthy is an iOS app that acts like a personal health advisor in your pocket. It tracks your health metrics, analyzes your habits, estimates your life expectancy, and gives you personalized recommendations — all powered by an AI assistant called **Pearl**.

Think of it as your smart health dashboard: connect it to Apple Health, log your meals, import blood test results, and Pearl will make sense of it all for you.

---

## What the App Does

- **Health Dashboard** — See all your key health stats (heart rate, steps, sleep, blood pressure, weight, and more) in one place
- **Pearl AI Chat** — Ask Pearl anything about your health and get personalized, data-driven answers
- **Life Expectancy Estimate** — See a running estimate of your lifespan based on your actual health data, and which habits are helping or hurting it
- **Disease Risk Assessment** — Get a clear breakdown of your risk for common conditions based on your profile and metrics
- **Nutrition Logger** — Log meals by searching foods or scanning barcodes; see your nutrition score
- **Habit Tracker** — Pearl recommends personalized health habits and tracks your progress
- **3D Body Visualization** — See a visual body model that reflects your height, weight, and body composition
- **Blood Test Import** — Upload your lab results and Pearl will analyze them for you
- **Apple Health Sync** — Automatically pulls in data from your iPhone's Health app

---

## What You'll Need Before Starting

You need a **Mac computer** to build and run this app (iPhones can't build apps by themselves). Here's everything you need:

| What | Why | Free? |
|------|-----|-------|
| A Mac running macOS 14 (Sonoma) or newer | Required to run Xcode | Yes (comes with Mac) |
| **Xcode 16** or newer | Apple's tool for building iPhone apps | Yes (free from App Store) |
| An Apple ID | Required to run the app on your phone | Yes |
| An iPhone running **iOS 18** or newer | To test on a real device (optional — simulator works too) | You likely already have one |
| **Homebrew** | A package manager for Mac (makes installing tools easy) | Yes |
| **XcodeGen** | A tool that sets up the Xcode project file | Yes |
| **CAESAR Body Model Data** | Required for the 3D body visualization feature — see the section below | Free (registration required) |

---

## Starting on a New Computer — Quick Start

If you just want the app running on a fresh Mac as fast as possible, do these three things in order:

### 1. Install Xcode from the Mac App Store

Open the **App Store**, search for **Xcode**, click **Get** / **Install** (it's ~15 GB — give it time). Once it finishes, open Xcode once so it can accept the license, then close it.

### 2. Get the code onto the Mac

Open **Terminal** (press `⌘ + Space`, type "Terminal", hit Enter) and run:

```
cd ~/Desktop
git clone https://github.com/rohangandotra18/APP-APTOSWASTHY.git APP
cd APP
```

> If you don't have `git` yet, macOS will prompt you to install the Xcode Command Line Tools — click **Install** and wait for it to finish, then re-run the `git clone` command.
>
> If you received the code as a ZIP instead, double-click to extract it, rename the folder to `APP`, and move it to your Desktop. Then `cd ~/Desktop/APP` in Terminal.

### 3. Run the setup script

From the `APP` folder in Terminal:

```
./setup.sh
```

This one command installs Homebrew (if missing), installs XcodeGen, generates the Xcode project, and opens it in Xcode for you.

### 4. Pick your Apple ID and press Play

When Xcode opens:

1. Click **AptoSwasthy** in the left sidebar (the blue project icon at the top)
2. Go to the **Signing & Capabilities** tab
3. Under **Team**, pick your Apple ID from the dropdown (add it via **Xcode → Settings → Accounts** if it isn't listed)
4. At the top of Xcode, pick an iPhone simulator (e.g. **iPhone 16 Pro**) or your connected iPhone
5. Press the **Play button** (▶) or `⌘ + R`

That's it — the app will build and launch. First build takes a few minutes; subsequent builds are fast.

> **About the 3D body model:** The app includes a pre-built `body_basis.bin` file, so the 3D body visualization works out of the box. You only need the raw CAESAR files if you want to rebuild that binary — see the [3D Body Model Data](#3d-body-model-data-required) section at the bottom.

---

## Step-by-Step Setup Guide (Manual — if the Quick Start fails)

Use this if `setup.sh` didn't work for any reason, or if you want to understand exactly what's happening.

### Step 1 — Install Xcode

1. Open the **App Store** on your Mac
2. Search for **Xcode**
3. Click **Get** and then **Install** (it's a large download — around 15GB, so give it time)
4. Once installed, open Xcode once to accept the license agreement, then close it

### Step 2 — Install Homebrew

Homebrew is like an "app store for developer tools." You only need to do this once.

1. Open the **Terminal** app on your Mac (search for "Terminal" in Spotlight — press `⌘ + Space` and type "Terminal")
2. Paste this entire command and press **Enter**:

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

3. Follow the on-screen prompts (it may ask for your Mac password)
4. When it finishes, close Terminal and reopen it

### Step 3 — Install XcodeGen

XcodeGen is a small tool that generates the Xcode project file from a configuration file. Run this in Terminal:

```
brew install xcodegen
```

Wait for it to finish. You'll see a success message when done.

### Step 4 — Download the App Code

If you received the code as a ZIP file:
1. Double-click the ZIP to extract it
2. Move the extracted folder somewhere easy to find (like your Desktop or Documents)

If you're cloning from GitHub:
```
git clone https://github.com/rohangandotra18/APP-APTOSWASTHY.git
```

### Step 5 — Generate the Xcode Project

1. Open **Terminal**
2. Navigate to the `AptoSwasthy` folder inside the project. For example, if you put the project on your Desktop:

```
cd ~/Desktop/APP/AptoSwasthy
```

3. Run this command:

```
xcodegen generate
```

You should see output ending in something like `✓ Generated project at AptoSwasthy.xcodeproj`. This creates the Xcode project file.

### Step 6 — Open the Project in Xcode

Still in Terminal, run:

```
open AptoSwasthy.xcodeproj
```

Xcode will open. Give it a minute to load and index the project files.

### Step 7 — Set Your Development Team

This tells Xcode which Apple account to use for running the app.

1. In Xcode, click on **AptoSwasthy** in the left sidebar (the blue icon at the very top)
2. In the main area, click the **Signing & Capabilities** tab
3. Under **Team**, click the dropdown and select your Apple ID
   - If you don't see your Apple ID, go to **Xcode → Settings → Accounts** and add it with the `+` button

> **Note:** With a free Apple ID, you can run the app on your own iPhone for up to 7 days before needing to re-install. A paid Apple Developer account ($99/year) removes this limit and lets you distribute the app.

### Step 8 — Run the App

**On the iOS Simulator (no iPhone needed):**
1. At the top of Xcode, click the device selector (it shows something like "iPhone 15" or "Any iOS Device")
2. Choose an iPhone model from the list (e.g., **iPhone 16 Pro**)
3. Press the **Play button** (▶) or press `⌘ + R`
4. The simulator will launch and the app will open automatically

**On your real iPhone:**
1. Connect your iPhone to your Mac with a cable
2. Select your iPhone from the device selector at the top of Xcode
3. On your iPhone, go to **Settings → General → VPN & Device Management** and trust your Apple ID
4. Press the **Play button** (▶) or press `⌘ + R`

The first build takes a few minutes. Subsequent builds are much faster.

---

## First Time Using the App

When you first open AptoSwasthy:

1. **Create an account** — Sign up with your email address. You'll receive a verification code.
2. **Grant permissions** — The app will ask for access to:
   - **Apple Health** — to read your health data (steps, heart rate, sleep, etc.)
   - **Camera** — for barcode scanning when logging food
   - **Face ID** — for secure login (optional)
   - **Notifications** — for habit reminders (optional)
3. **Complete onboarding** — Answer questions about your health, lifestyle, and goals. This helps Pearl give you personalized insights.
4. **Explore!** — Your dashboard will start populating once the app reads your Apple Health data.

---

## Troubleshooting

**"No such module" error in Xcode**
→ Make sure you ran `xcodegen generate` in the `AptoSwasthy` folder before opening Xcode.

**"Signing certificate" error**
→ Go to **Signing & Capabilities** in Xcode and make sure your Apple ID is selected under **Team**.

**App crashes immediately on launch**
→ Make sure your device or simulator is running **iOS 18 or newer**.

**Build fails with "Swift compiler" errors**
→ Make sure you have **Xcode 16 or newer**. Go to **Xcode → About Xcode** to check your version.

**"Could not launch app" on real iPhone**
→ On your iPhone, go to **Settings → General → VPN & Device Management**, find your Apple ID, and tap **Trust**.

**Simulator is very slow**
→ Try a different simulator, iPhones with "Pro" in the name tend to perform better. Also make sure your Mac has at least 8GB of RAM.

---

## 3D Body Model Data (Required)

The app includes a feature that shows a 3D body model that adapts to your height, weight, and body composition. This model is powered by the **CAESAR anthropometric dataset** — a large scientific dataset of real human body measurements.

The pre-processed model file (`body_basis.bin`) is already included in this repo and the app will work out of the box. **You only need to follow the steps below if you ever need to rebuild that file from scratch** (for example, after modifying the Python conversion script).

### What are these files?

The raw data comes from the **HumanShape / CAESAR-norm-WSX** dataset, published by Pishchulin et al. (2015) in the paper *"Building Statistical Shape Spaces for 3D Human Modeling"* from the Max Planck Institute for Informatics. It is licensed for non-commercial use only.

The four raw data files are:

| File | Size | What it contains |
|------|------|-----------------|
| `meanShape.mat` | ~1 MB | The average human body mesh (6,449 points) |
| `evalues.mat` | ~1 MB | How much each body shape component varies |
| `evectors.mat` | ~610 MB | All the possible body shape variations |
| `model.dat` | ~1 MB | The mesh triangle structure |

### Where to download them

1. Go to the **Max Planck Institute for Informatics HumanShape project page**:
   `https://humanshape.mpi-inf.mpg.de`
2. Register for a free account (required for non-commercial download)
3. Download the **CAESAR-norm-WSX** dataset package
4. Extract the ZIP — you'll find the four files listed above inside

### Where to put them

Once downloaded, create a folder called `caesar-norm-wsx` in the root of this project and place all four files inside it:

```
APP/
└── caesar-norm-wsx/
    ├── meanShape.mat
    ├── evalues.mat
    ├── evectors.mat
    └── model.dat
```

### How to rebuild `body_basis.bin` (optional)

If you need to regenerate the pre-processed binary from the raw files:

1. Make sure Python 3 is installed on your Mac (check by running `python3 --version` in Terminal)
2. Install the required Python packages:
   ```
   pip3 install numpy scipy
   ```
3. Run the conversion script from the project root:
   ```
   python3 AptoSwasthy/tools/convert_humanshape.py
   ```
   This takes a few minutes (the `evectors.mat` file is 610 MB). When done, it overwrites `body_basis.bin` inside the app's Resources folder automatically.

> **Note:** The `caesar-norm-wsx/` folder is excluded from this GitHub repository because the files are too large for GitHub (610 MB). They live on your Mac only.

---

## Project Structure (for the curious)

```
APP/
├── AptoSwasthy/          — The iOS app code
│   ├── Sources/          — All Swift source code
│   │   ├── App/          — App entry point and main navigation
│   │   ├── AI/           — Pearl chat interface
│   │   ├── Pearl/        — Pearl's health analysis engines
│   │   ├── Home/         — Dashboard, habits, nutrition logger
│   │   ├── Risks/        — Disease risk assessment
│   │   ├── You/          — Profile and 3D body model
│   │   ├── Authentication/ — Login, sign up, password reset
│   │   ├── Services/     — Apple Health, data storage, notifications
│   │   └── Models/       — Data structures (User, Meal, Habit, etc.)
│   ├── infra/            — Backend server code (AWS Lambda)
│   └── project.yml       — Xcode project configuration
├── appicon.png           — App icon reference
└── README.md             — This file
```
