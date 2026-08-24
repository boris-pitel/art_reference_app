# Putting Painter Reference on an iPhone from a borrowed Mac

Free provisioning: no paid Apple Developer account, no TestFlight, and the app
**stops working after 7 days**. To keep it on the phone you repeat this. That is
the trade for not paying the $99 a year.

Everything the app needs to run is committed, including `env` with the Supabase
URL and key, so a clone is enough — nothing has to be copied across by hand.

## Before you sit down at the Mac

You need the phone, its cable, and the Apple ID you use on that phone. Use the
**same Apple ID on the Mac and the iPhone**; a certificate issued to one Apple
ID will not install on a device signed in with another.

Allow about an hour the first time. Most of it is Xcode and CocoaPods
downloading.

## 1. Tools

```bash
xcode-select --install          # command line tools, if not already there
brew install --cask flutter     # or download from flutter.dev
sudo gem install cocoapods      # Flutter needs this for iOS
flutter doctor                  # fix anything it complains about for iOS
```

Xcode itself comes from the App Store and is a large download. If the Mac
already has it, check it is recent enough for the installed Flutter — `flutter
doctor` says so plainly.

## 2. The project

```bash
git clone https://github.com/boris-pitel/art_reference_app.git
cd art_reference_app
flutter pub get
```

## 3. Sign in to Xcode

Xcode → Settings → Accounts → **+** → Apple ID → sign in.

This creates a "Personal Team", which is what free provisioning uses. No paid
membership is involved.

## 4. Open the workspace, not the project

```bash
open ios/Runner.xcworkspace
```

`Runner.xcodeproj` looks right and will fail once CocoaPods is involved. Always
the `.xcworkspace`.

In Xcode: select **Runner** in the left sidebar, then the **Runner** target,
then **Signing & Capabilities**.

- Tick **Automatically manage signing**
- **Team**: your Personal Team
- **Bundle Identifier**: `com.painterreference.app`

If Xcode reports the bundle identifier is unavailable, someone else has
registered it. Change it to something unique — `com.yourname.painterreference`
— and note that this makes it a different app to iOS, so the one already on the
phone is unaffected.

## 5. The phone

Plug it in. Unlock it. Tap **Trust** on the prompt. Select the device from the
target dropdown at the top of the Xcode window.

## 6. Build

Either press Run in Xcode, or from the terminal:

```bash
flutter devices                             # find the device id
flutter run --release -d <device-id>
```

Release rather than debug: a debug build is slower and expires the same way, so
there is no reason to test against one.

The first build takes several minutes while CocoaPods fetches every plugin's
iOS code. Later builds are much faster.

## 7. Trust the certificate on the phone

The first install fails to launch with "Untrusted Developer". On the iPhone:

**Settings → General → VPN & Device Management → your Apple ID → Trust**

Then open the app normally.

## Known gaps on iOS

**Sharing into the app will not work.** `receive_sharing_intent` needs a Share
Extension target added in Xcode plus an App Group, and this project has neither
— `ios/` contains only Runner and RunnerTests. The app builds and runs fine
without it; only "share a photo from another app into Painter Reference" is
missing. Setting it up is a job for the Mac session if you want that feature.

**Google sign-in is untested on native iOS.** The URL scheme is registered in
`Info.plist`, but nobody has run it. Email sign-in is the safe path.

## What free provisioning costs you

- The app dies after 7 days and must be rebuilt from a Mac
- Three free-provisioned apps per device at a time
- Ten new app identifiers per week across your Apple ID
- Your own devices only — testers cannot be given a build

If any of that becomes annoying, that annoyance is exactly what the $99 buys
away: TestFlight installs over the air, to anyone, and builds that do not
expire.
