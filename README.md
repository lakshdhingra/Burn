# 🔥 ThermaLink

> Industrial Heat Exchange & Matching Platform
> Connecting waste heat sources with demand sinks to reduce cost and carbon emissions.

---

## 🚀 Overview

**ThermaLink** is a smart platform that connects industries producing excess heat (**sources**) with industries that require heat (**sinks**).

It helps:

* ♻️ Reduce energy waste
* 💰 Save operational costs
* 🌍 Lower carbon emissions

---

## ✨ Features

### 🔐 Authentication

* Login & Signup using Supabase

### 🏭 Factory Management

* Add **Heat Source** data
* Add **Heat Sink** data
* Store and manage data via Supabase

### 🔍 Smart Matching System

* Matches sources and sinks based on:

  * Temperature compatibility
  * Heat capacity
  * Operating hours

### 📊 Advanced Calculations

* Energy Saved (kWh/year)
* Cost Saved (₹/year)
* CO₂ Reduction (kg/year)
* ROI (Return on Investment)

### 🗺️ Map Integration

* Visualize sources and sinks
* Distance-based matching

### ⭐ Save Matches

* Save selected matches to database

### 🎨 Modern UI

* Gradient-based design
* Glassmorphism cards
* Smooth animations

---

## 🧠 How It Works

1. User logs in
2. Adds factory data (source or sink)
3. System calculates matches
4. Displays best matches with:

   * ROI
   * Cost savings
   * CO₂ reduction
5. User can save and analyze matches

---

## ⚙️ Tech Stack

### 🖥️ Frontend

* Flutter (Dart)

### 🔗 Backend

* Supabase (Auth + PostgreSQL)

### 📍 Maps

* OpenStreetMap (via flutter_map)

---

## 📦 Flutter Dependencies

Add these in your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Supabase
  supabase_flutter: ^2.0.0

  # Maps
  flutter_map: ^6.0.0
  latlong2: ^0.9.0

  # UI / Icons
  cupertino_icons: ^1.0.6

  # (Optional but useful)
  google_fonts: ^6.1.0
```

---

## 📐 Core Formulas

```
Energy Saved = Heat × Hours × 365

Cost Saved = Energy × ₹8 per kWh

CO₂ Saved = Energy × 0.82 kg

ROI = Cost Saved / Installation Cost (~₹5L)
```

---

## 📁 Project Structure

```
lib/
 ├── pages/
 │   ├── login/
 │   ├── dashboard/
 │   ├── matches/
 │   ├── profile/
 │   ├── map/
 │   └── factory/
 ├── services/
 └── main.dart
```

---

## 🛠️ Setup Instructions

### 1️⃣ Install dependencies

```bash
flutter pub get
```

---

### 2️⃣ Add Supabase Credentials

```dart
const supabaseUrl = "YOUR_URL";
const supabaseAnonKey = "YOUR_KEY";
```

---

### 3️⃣ Run the app

```bash
flutter run
```

---

## 🧪 Future Improvements

* 🤖 AI-based match recommendations
* 📄 Proposal generation
* 💬 Industry chat system
* 📊 Advanced analytics

---

## 🏆 Use Case

* Steel plants
* Textile industries
* Food processing
* Chemical industries

---

## 👨‍💻 Team

* Laksh Dhingra
* Suhani Jain
* Rajashree Saha
* Amit Kumar

---

## 💡 Tagline

> "Turning Waste Heat into Smart Energy Connections"
