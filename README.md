<img src="Detent/Assets.xcassets/AppIcon.appiconset/icon-128.png" width="96" alt="Detent icon">

# Detent

A two-factor authentication app for the macOS menu bar, with a command line tool that prints codes so your terminal can enter them for you.

- **Scan from the screen.** Put a 2FA setup QR code anywhere on any display and Detent finds it. No camera, no cropping.
- **Or paste.** Add an account from an `otpauth://` link or the bare secret key.
- **Live codes.** Each account shows its current code and a countdown; click to copy.
- **`detent` command.** `detent github` prints the current code for the matching account.
- **iCloud sync and backups.** Optionally keep accounts in iCloud Keychain, and export them to an encrypted file.

## Install

Download the latest zip from [Releases](https://github.com/colinbm/detent/releases/latest), unzip it, and move `Detent.app` to Applications. The app is signed and notarized.

Requires macOS 14 or later, on Apple silicon or Intel.

The first scan asks for Screen Recording permission: allow Detent under System Settings › Privacy & Security › Screen & System Audio Recording, then scan again.

## Command line tool

The tool ships inside the app. Choose **Install Command Line Tool…** from the **…** menu to copy a command that links it into `/usr/local/bin`, then paste that into a terminal.

```
detent <name>   print the current code for the matching account
detent list     list accounts
detent chrome-setup   let the Chrome extension fetch codes
```

Accounts are added and removed in the app.

`<name>` matches the issuer, the account name or `issuer:name`, ignoring case. Failing an exact match, any unique substring will do. `-n` omits the trailing newline.

The first time the tool reads the accounts, macOS asks for your login keychain password. Choose **Always Allow**.

### Entering codes automatically in iTerm

In Settings › Profiles › Advanced › Triggers, add a trigger:

| Field | Value |
| --- | --- |
| Regular expression | the prompt to react to, such as `Verification code:` |
| Action | Run Coprocess |
| Parameters | `/usr/local/bin/detent github` |

The tool's output is typed into the session, and the trailing newline submits it.

## Chrome extension

The extension fills in the code when a site you have chosen asks for one. It gets each code from the `detent` tool, so the secrets stay in the keychain and the extension never sees them.

Install it from the [Chrome Web Store](https://chromewebstore.google.com/detail/jidikgloajdnephgadlaglogblccjejk):

1. Choose **Set Up Chrome Extension…** from the **…** menu, then **Copy Command and Open Store**.
2. Paste the command into a terminal. It runs `detent chrome-setup`, which tells Chrome where the tool is. It also covers Chrome Beta and Canary, Chromium, Brave, Edge, Vivaldi and Arc.
3. Click **Add to Chrome** on the store page.
4. Open the site's sign-in page, click the Detent toolbar button, choose the account and click **Fill codes on this site**. Chrome asks you to allow Detent on that site.

If you move Detent, run the command again.

To work on the extension, load the `chrome-extension` folder unpacked from `chrome://extensions` with **Developer mode** on. Its manifest `key` gives it a fixed ID that the `detent` tool also accepts. The store rejects that key, so remove it from the copy you zip for upload.

From then on, when a page on that site or its subdomains shows a field for a two-factor code, Detent fills it in. Tick **Submit the form after filling** to have it press the button as well. The same popup lists the sites you have set up and removes them.

The extension can only read pages on the sites you add, and only asks for a code once a code field is on the page. A code is never entered twice in the same tab: if a page asks again, Detent waits for the next one. If no code appears, the toolbar button shows a red **!**; hover over it for the reason. Fields inside embedded frames are not filled.

## iPhone and iPad

The Detent iOS app shows the same accounts as the Mac when **Sync with iCloud Keychain** is on there. Add accounts by scanning a QR code with the camera, choosing a photo or screenshot of one, or entering the key.

### AutoFill

Turn on Detent in Settings › General › AutoFill & Passwords (iOS 18 or later). When a page or app asks for a verification code, tap the field, choose **AutoFill** › **Passwords** and pick the account. Detent remembers which site you picked it for, and from then on offers that account's code above the keyboard there in one tap.

### AutoFill on the Mac

On macOS 15 or later, choose **AutoFill Settings…** from the **…** menu to turn on Detent as a verification code provider (it is under System Settings › General › AutoFill & Passwords). It works like the iPhone's: Safari and other apps offer codes for the sites Detent knows, and picking an account from the AutoFill menu teaches it the site. It works whether or not iCloud sync is on: the app keeps a copy of the accounts that the extension can read, in the keychain group they share, and takes back any sites the extension learns.

### Sites

Each account keeps a list of the sites it signs in to, which is what AutoFill uses to suggest it. Sites are added when:

- the Mac scans the QR code from a browser window. Detent asks Safari, Chrome, Brave, Edge, Vivaldi or Arc for the page's address; macOS asks once per browser whether Detent may do that.
- the setup code's issuer is itself a domain, such as "Amazon.com".
- you set up the Chrome extension on a site.
- you pick the account from AutoFill on the Mac, iPhone or iPad.

To change them, swipe right on an account in the iOS app and tap **Sites**, or choose **Edit Sites…** from an account's context menu on the Mac. Sites are shared through iCloud Keychain like the rest of the account, and the latest change to each site wins, so a site removed on one device stays removed everywhere until someone adds it back. When the Chrome extension records a site, the `detent` tool tells the Mac app, which copies it to iCloud straight away.

## Where secrets are stored

By default, accounts live in a single item, "Detent accounts", in your login keychain. They stay on this Mac.

### iCloud sync

Turn on **Sync with iCloud Keychain** in the **…** menu to keep accounts in iCloud Keychain instead, end-to-end encrypted by Apple and shared with your other Macs running Detent. It needs iCloud Keychain switched on in System Settings.

Turning it on never loses anything already on the Mac: accounts only on this Mac are uploaded, and if one shares an issuer and name with a different account in iCloud, both are kept and the local one gets a numbered name such as "me (2)". Deleting an account leaves a deletion record in iCloud, so other devices remove it too rather than mistaking it for one that has not synced yet.

The app then keeps the local keychain item as a copy, because the `detent` tool can only read that. The copy is refreshed whenever the app is opened and every few minutes while it runs, so turn on **Launch at Login** to keep the tool up to date with accounts added on other devices.

### Backups

**Export Accounts…** writes every account to a file encrypted with a passphrase you choose (AES-256-GCM, key derived with PBKDF2). **Import Accounts…** reads one back. The passphrase cannot be recovered, so keep it somewhere safe.

Only time-based (TOTP) codes are supported.

## Building

Open `Detent.xcodeproj` in Xcode 27, or build from the command line:

```
xcodebuild -target Detent -configuration Release build SYMROOT=build
```

Building the app also builds the `detent` tool and embeds it at `Detent.app/Contents/Helpers/detent`. Set your own development team in the project's build settings to sign it.

The app icon is drawn by `Tools/make-icon.swift`.

`scripts/testflight.sh` uploads an iOS build. `scripts/appstore.rb` fills in the App Store listing from `AppStore/metadata.json` and uploads the screenshots in `AppStore/screenshots`, which come from a Debug build launched with `-DetentDemo YES` to show made-up accounts.
