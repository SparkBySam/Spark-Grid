# Spark Grid — Mac App Store submission checklist

Version **1.0** (build **2**) · Bundle ID `com.sparkbysam.SparkGrid` · Team `ULS58DAH92`

**Status: Address App Review — 5.2.5 (subtitle “Mac”) + 3.1.1 (tip jar)**

See `APP_REVIEW_RESPONSE.md` for the Resolution Center reply.

## Already in the project

- [x] Bundle ID: `com.sparkbysam.SparkGrid`
- [x] Team: `ULS58DAH92`
- [x] Marketing version **1.0**, build **2**
- [x] macOS **14.0+**, category Productivity (built & smoke-tested on macOS 27 / Xcode 27)
- [x] Sandbox: user-selected files + printing; hardened runtime on
- [x] `ITSAppUsesNonExemptEncryption = false`
- [x] `PrivacyInfo.xcprivacy` (UserDefaults CA92.1; no tracking / no collected data)
- [x] xlsx `LSHandlerRank` Alternate; CSV Default
- [x] Amber App Icon asset set
- [x] Privacy: [https://sparkgridapp.com/privacy](https://sparkgridapp.com/privacy)
- [x] Terms: [https://sparkgridapp.com/legal](https://sparkgridapp.com/legal)
- [x] **No in-app tip jar / external donations** (removed for Guideline 3.1.1)

---



## 1. Apple Developer / App Store Connect

- [x] Confirm paid Apple Developer membership is active
- [x] Register App ID `com.sparkbysam.SparkGrid`
- [x] Create Mac app record in App Store Connect (same bundle ID)
- [x] Pricing: Free (or set price)
- [x] Age rating questionnaire
- [x] Privacy Nutrition Labels: **Data Not Collected**
- [x] Encryption: **No** (matches plist exemption)
- [x] Support URL: `https://sparkgridapp.com/support`
- [x] Support email: `help@sparkgridapp.com`
- [x] Marketing URL (optional): `https://sparkgridapp.com`
- [x] Privacy Policy URL: `https://sparkgridapp.com/privacy`
- [x] Copyright: `2026 Sam Parker`



## 2. Listing copy

- [x] App name: **Spark Grid**
- [x] Subtitle (~30 chars): **`XLSX & CSV spreadsheet`** (no “Mac” — 5.2.5; no “Excel” — 4.1(c))
- [x] Promotional text (≤170 chars) — paste:

```
Free native spreadsheet — open and save Excel .xlsx and CSV. Formulas, filters, charts, and formatting without the browser bloat.
```

- [x] Description — paste:

```
Spark Grid is a free native spreadsheet for people who want Excel-compatible files without dragging a browser into everyday work.

Open and edit real workbooks. Spark Grid reads and writes Excel .xlsx and CSV, so your files stay useful wherever you already work.

Built as native desktop software. A custom App Grid with sticky headers, freeze panes, fill handle, and keyboard navigation — not a web app in a wrapper.

Formulas that make sense. Formula bar, autocomplete, and clear errors when something goes wrong. Totals, averages, and everyday logic without fighting the sheet.

Polish for real work. Formatting toolbar, filters, conditional formatting, charts, and embedded pictures. Multi-sheet workbooks with a clean dark interface.

Privacy by default. No account required. No analytics. Your spreadsheets stay on your device.

Part of the Spark Suite — small, sharp productivity tools.

Requirements: macOS 14 or later.

Support: https://sparkgridapp.com/support
Privacy: https://sparkgridapp.com/privacy
```

- [x] Keywords
- [x] What’s New for 1.0
- [x] Category: Productivity (secondary optional)



## 3. Screenshots / icon

- [x] Mac screenshots at **2880 × 1800**, PNG, no alpha (see `AppStoreScreenshots/`)
- [x] Scenes: pipeline, Weekly Calls, totals/formula (no tip-jar About shot)
- [x] Upload **`01`–`03` only** in App Store Connect → Mac screenshots (skip `04`)
- [x] Confirm App Icon looks correct at all sizes in Xcode Assets (amber mark)



## 4. Build & upload

- [x] Scheme: **Spark Grid** → Release, destination **Any Mac**
- [x] Signing: **Apple Distribution** / automatic with team `ULS58DAH92`
- [x] Product → **Archive**
- [x] Organizer → **Distribute App** → App Store Connect → Upload
- [x] Wait for build processing; select build on the version



## 5. Pre-submit smoke (Release build)

- [ ] New workbook, edit cells, undo/redo
- [ ] Open/save `.xlsx` and `.csv` (sandbox file picker)
- [ ] Finder Quick Look: Space on `.csv` / `.xlsx` → grid preview, edit a cell, Save
- [ ] Formulas (`SUM`, etc.), formatting, filters
- [ ] Insert chart; insert/move picture
- [ ] About → Privacy / Terms open sparkgridapp.com
- [ ] No crash on empty sheet / large-ish CSV
- [ ] Confirm no debug-only entitlements left



## 6. Review notes (optional but useful)

- [ ] Note: offline spreadsheet; opens user-selected Excel/CSV only; no account/login
- [ ] Point reviewers at sample: `web/samples/Q3-Enterprise-Pipeline.xlsx` if you attach or describe it



## 7. Submit

- [x] All required metadata + screenshots attached
- [x] Build selected
- [x] Export compliance answered
- [x] **Add for Review** → **Submit to App Review**

---



## Suggested order

1. Connect app record + privacy URLs
2. Screenshots
3. Archive / upload
4. Smoke test
5. Submit



## Quick reference


| Field           | Value                                                                |
| --------------- | -------------------------------------------------------------------- |
| Bundle ID       | `com.sparkbysam.SparkGrid`                                           |
| Team            | `ULS58DAH92`                                                         |
| Version / build | `1.0` / `2`                                                          |
| Min OS          | macOS 14.0 (tested on macOS 27)                                      |
| Privacy         | [https://sparkgridapp.com/privacy](https://sparkgridapp.com/privacy) |
| Terms           | [https://sparkgridapp.com/legal](https://sparkgridapp.com/legal)     |
| Support         | [https://sparkgridapp.com/support](https://sparkgridapp.com/support) |
| Support email   | `help@sparkgridapp.com`                                              |
| Marketing       | [https://sparkgridapp.com](https://sparkgridapp.com)                 |
| Sample workbook | `web/samples/Q3-Enterprise-Pipeline.xlsx`                            |


