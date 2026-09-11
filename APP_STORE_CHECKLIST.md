# Spark Grid — Mac App Store submission checklist

Version **1.0** (build **1**) · Bundle ID `com.sparkbysam.SparkGrid` · Team `ULS58DAH92`

## Already in the project

- [x] Bundle ID: `com.sparkbysam.SparkGrid`
- [x] Team: `ULS58DAH92`
- [x] Marketing version **1.0**, build **1**
- [x] macOS **14.0+**, category Productivity
- [x] Sandbox: user-selected files + printing; hardened runtime on
- [x] `ITSAppUsesNonExemptEncryption = false`
- [x] `PrivacyInfo.xcprivacy` (UserDefaults CA92.1; no tracking / no collected data)
- [x] xlsx `LSHandlerRank` Alternate; CSV Default
- [x] Amber App Icon asset set
- [x] Privacy: [https://sparkgridapp.com/privacy](https://sparkgridapp.com/privacy)
- [x] Terms: [https://sparkgridapp.com/legal](https://sparkgridapp.com/legal)

---



## 1. Apple Developer / App Store Connect

- [x] Confirm paid Apple Developer membership is active
- [x] Register App ID `com.sparkbysam.SparkGrid`
- [x] Create Mac app record in App Store Connect (same bundle ID)
- [ ] Pricing: Free (or set price)
- [ ] Age rating questionnaire
- [ ] Privacy Nutrition Labels: **Data Not Collected**
- [ ] Encryption: **No** (matches plist exemption)
- [ ] Support URL: `https://sparkgridapp.com/support`
- [ ] Support email: `help@sparkgridapp.com`
- [ ] Marketing URL (optional): `https://sparkgridapp.com`
- [ ] Privacy Policy URL: `https://sparkgridapp.com/privacy`
- [ ] Copyright: `2026 Sam Parker`



## 2. Listing copy

- [ ] App name: **Spark Grid**
- [ ] Subtitle (~30 chars), e.g. `Native Mac spreadsheet`
- [ ] Description (features, Excel/CSV, free, macOS 14+)
- [ ] Keywords
- [ ] What’s New for 1.0
- [ ] Category: Productivity (secondary optional)



## 3. Screenshots / icon

- [ ] Mac screenshots (required sizes for current Connect — typically 1280×800 or 1440×900 / 2880×1800)
- [ ] Use real in-app shots (pipeline + Weekly Calls under `web/images/`)
- [ ] Confirm App Icon looks correct at all sizes in Xcode Assets (amber mark)
- [ ] No placeholder / debug UI in shots



## 4. Build & upload

- [ ] Scheme: **Spark Grid** → Release, destination **Any Mac**
- [ ] Signing: **Apple Distribution** / automatic with team `ULS58DAH92`
- [ ] Product → **Archive**
- [ ] Organizer → **Distribute App** → App Store Connect → Upload
- [ ] Wait for build processing; select build on the version



## 5. Pre-submit smoke (Release build)

- [ ] New workbook, edit cells, undo/redo
- [ ] Open/save `.xlsx` and `.csv` (sandbox file picker)
- [ ] Formulas (`SUM`, etc.), formatting, filters
- [ ] Insert chart; insert/move picture
- [ ] About → Privacy / Terms open sparkgridapp.com
- [ ] No crash on empty sheet / large-ish CSV
- [ ] Confirm no debug-only entitlements left



## 6. Review notes (optional but useful)

- [ ] Note: offline spreadsheet; opens user-selected Excel/CSV only; no account/login
- [ ] Point reviewers at sample: `web/samples/Q3-Enterprise-Pipeline.xlsx` if you attach or describe it



## 7. Submit

- [ ] All required metadata + screenshots attached
- [ ] Build selected
- [ ] Export compliance answered
- [ ] **Add for Review** → **Submit to App Review**

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
| Version / build | `1.0` / `1`                                                          |
| Min OS          | macOS 14.0                                                           |
| Privacy         | [https://sparkgridapp.com/privacy](https://sparkgridapp.com/privacy) |
| Terms           | [https://sparkgridapp.com/legal](https://sparkgridapp.com/legal)     |
| Support         | [https://sparkgridapp.com/support](https://sparkgridapp.com/support) |
| Support email   | `help@sparkgridapp.com`                                              |
| Marketing       | [https://sparkgridapp.com](https://sparkgridapp.com)                 |
| Sample workbook | `web/samples/Q3-Enterprise-Pipeline.xlsx`                            |


