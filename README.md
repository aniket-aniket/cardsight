# Cardsight: Pokémon card scanner and price checker

Cardsight is a native iPhone app written in SwiftUI. Take a photo of a Pokémon card, or pick one from your library. The app identifies the card and shows its current TCGplayer market value in USD.

The app was renamed from CardLens. Its Xcode project, target and folder are still called `CardLens`, so the setup steps below use that name; the name on the Home Screen and inside the app is Cardsight.

## What it does

| Step | How it works |
|---|---|
| **Capture** | Uses the camera (after asking for permission) or a photo-library picker. The picker needs no permission prompt because it runs outside the app. |
| **Review & crop** | Finds the card's edges automatically with Vision and straightens the image. You can drag the corners to adjust, rotate the photo, or use the whole photo. |
| **Identify** | Reads the card name and collector number on the phone (Vision text recognition), then searches the **TCGdex** card database. Candidates are re-ranked by comparing your photo with each official card image. Reprints with the same art are told apart by the set total (e.g. `4/102` vs `4/130`). |
| **Confidence** | Shows High, Medium or Low with an icon, a text label and a percentage. Confidence is never "High" when the card number couldn't be read or when two candidates are nearly tied. |
| **Price** | A separate step that requests the identified card's current **TCGplayer** USD prices from TCGdex. Shows the market price per printing (normal, holo, reverse holo…), the low–high range, the source, when the provider last updated it, and when the app checked. If no price exists, it says **"Live price unavailable"**. It never guesses. |
| **Other matches** | Lists other likely cards. Tap one to switch to it and re-price it. |
| **Printing / foil pricing** | When a card has several printings (Normal, Holofoil, Reverse Holofoil…), you pick the one you have and the headline price follows. The likely one is pre-selected from the card's rarity and marked "Suggested". The app doesn't try to detect foil from the photo, because glare makes that unreliable. |
| **Collection** | **Add to Collection** with printing, condition and quantity. Adding the same card again increases its quantity. The Collection tab shows total value, sorting, pull-to-refresh of every price, and a detail screen per card. |
| **Duplicate warning** | When you scan a card you already own, a banner shows how many copies you have and in which printing and condition. |
| **Price tracking** | Every price check saves a snapshot (repeats of the same provider update are skipped). There are per-printing price history charts and a collection value chart. The free source has no history, so charts start from your first check. |
| **Centering grader** | Measures the four border widths on the straightened photo, shows left/right and top/bottom splits, and compares them with PSA's front-centering limits. It's labelled as an estimate and covers centering only; corners, edges and surface need an in-hand inspection. It says when it can't measure, e.g. full-art cards with no plain border. |
| **Recent scans** | Saved on the device (SwiftData) with the last checked price. Tap a scan to refresh its price; swipe left to delete. |

Accessibility:
- Every screen supports Dynamic Type, and layouts rearrange at the largest text sizes.
- VoiceOver reads the card name, set, number, rarity, confidence and price as one element, and announces progress ("Identifying card", "Match found…", the price).
- Crop corners can be moved with VoiceOver by swiping up or down.

## Data sources and API keys

| Purpose | Source | Key needed? |
|---|---|---|
| Card catalog, images, set info | [TCGdex API](https://tcgdex.dev) (`api.tcgdex.net/v2/en`) | **No** |
| Prices | TCGplayer market data, published by TCGdex for each card | **No** |
| Text recognition, image comparison | Apple Vision, on the device | No |

**No backend is required to run the app.** No secrets are stored in it.

### Using a keyed pricing provider (optional, later)
If you later want another provider, such as Scrydex (the paid successor to pokemontcg.io), **don't put its API key in the app**. Anything shipped in an app can be extracted. Instead:

1. Run a small proxy server, for example a Cloudflare Worker or a Vercel or Firebase function. It keeps the key in a server-side environment variable and forwards requests to the provider.
2. Add a new type that conforms to `PriceService` (see `CardLens/Data/PriceService.swift`) and calls your proxy.
3. Swap it in where `PriceLoader` is created (`CardLens/Result/PriceSection.swift`).

The identification step never needs to change, because pricing is a separate protocol.

## Project layout
```
CardLens.xcodeproj
CardLens/
  App/        App entry point and tabs
  Scan/       Home, camera, crop and review, identifying, flow state
  Identify/   Text parser, Vision text recognition, visual matcher, scoring, identifier
  Data/       TCGdex client, models, price service, errors, network monitor
  Result/     Result screen, price section (printing picker), price history chart, other matches
  Collection/ Collection items, add sheet, collection screen, valuation and value history
  Grading/    Centering analyzer and its result card
  History/    SwiftData scan records, Recent Scans
  Shared/     Reusable UI components, image helpers
CardLensTests/  Unit tests: parser, scoring, price decoding, collection, price history, centering
```
There are no third-party packages, so you don't need to add anything with Swift Package Manager.

---

# Beginner guide: run it in Xcode

Labels: **🧑 You (in Xcode)** = steps you do. **🤖 Claude (done in files)** = already done for you.

### 1. 🤖 Project files: already done
- Created the Xcode project, all the Swift code, the app icon and the unit tests.
- Added the camera and photo library permission messages. They live in the target's build settings, so there's no separate `Info.plist` file to edit.
- Set the iPhone deployment target to iOS 17.0.

### 2. 🧑 Make sure Xcode can build for iOS (one time)
Xcode needs its iOS platform component installed.
1. Open **Xcode**.
2. In the menu bar at the very top of the screen, click **Xcode › Settings…** (or press **⌘,**).
3. Click the **Components** tab. In older Xcode versions it's called **Platforms**.
4. If **iOS** shows a **Get** button, click it and wait for the download to finish.

### 3. 🧑 Open the project
1. In **Finder**, go to **Desktop › Projects › apps w raxit › CardLens**.
2. Double-click **`CardLens.xcodeproj`**. It has a blue blueprint icon.
3. The left sidebar is the **Project navigator**. If it's hidden, press **⌘1**. You'll see the `CardLens` and `CardLensTests` folders.

### 4. 🧑 Choose the app target and a simulator
At the top centre of the Xcode window is the **toolbar**. It shows something like `CardLens › iPhone 16 Pro`.
1. Click the left half (the **scheme**) and make sure **CardLens** is selected.
2. Click the right half (the **run destination**) and choose a simulator under **iOS Simulators**, for example **iPhone 16 Pro**.

### 5. 🧑 (Optional) Look at the permission settings
1. In the Project navigator, click the blue **CardLens** project icon at the very top.
2. In the middle pane, under **TARGETS**, click **CardLens**.
3. Click the **Info** tab. You'll see two entries that Claude added:
   - **Privacy - Camera Usage Description**
   - **Privacy - Photo Library Usage Description**

   iOS shows this text when it asks for access. You don't need to change anything.

### 6. 🧑 Build and run
1. Press the **▶︎ Run** button at the top left, or press **⌘R**.
2. The first build takes a minute. Then the Simulator opens and launches Cardsight.
3. If the build fails, open the **Issue navigator** (press **⌘5**) to read the error.

### 7. 🧑 Try a scan in the Simulator
The Simulator has no camera, so use the library:
1. Save a photo of a Pokémon card to your Mac. Your own photo is best; a picture from the web also works.
2. **Drag the image file onto the Simulator window.** It's saved to the simulator's Photos app.
3. In Cardsight, tap **Choose from Library**, pick the photo, check the outline, and tap **Identify Card**.

### 8. 🧑 Run the tests
Press **⌘U**, or choose **Product › Test** from the menu. Results appear in the **Test navigator** (press **⌘6**).

### 9. 🧑 Run on your real iPhone (to use the camera)
1. Add your Apple ID: go to **Xcode › Settings… › Accounts**, click **+**, choose **Apple ID** and sign in. A free account is fine.
2. Click the blue **CardLens** project icon, then **TARGETS › CardLens › Signing & Capabilities**.
3. Make sure **Automatically manage signing** is ticked, then choose your name under **Team**.
4. If Xcode says the bundle identifier is taken, change **Bundle Identifier** to something unique, such as `com.yourname.CardLens`.
5. Connect your iPhone with a cable and unlock it. Tap **Trust** if asked.
6. Choose your iPhone in the run destination menu (step 4) and press **⌘R**.
7. The first time only:
   - On the iPhone, turn on **Settings › Privacy & Security › Developer Mode**. The phone restarts.
   - If iOS says the developer is untrusted, go to **Settings › General › VPN & Device Management**, tap your Apple ID, and tap **Trust**.

## Troubleshooting
- **"iOS 18.x is not installed"**: do step 2.
- **"Camera unavailable"** in the Simulator: this is expected. Use **Choose from Library**.
- **"Couldn't identify this card"**: retake the photo with the whole card in frame, even lighting and no glare. Make sure the name (top) and the number (bottom corner) are sharp.
- **"Live price unavailable"**: TCGplayer has no current USD market price for that card. This is common for some promos and very new sets.
- **Japanese or other non-English cards**: the app searches the English catalog, so these may not match.
