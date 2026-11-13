<img src="Sesame/Assets.xcassets/AppIcon.appiconset/icon-128.png" width="96" alt="Sesame icon">

# Sesame

A two-factor authentication app for the macOS menu bar, with a command line tool that prints codes so your terminal can enter them for you.

- **Scan from the screen.** Put a 2FA setup QR code anywhere on any display and Sesame finds it. No camera, no cropping.
- **Or paste.** Add an account from an `otpauth://` link or the bare secret key.
- **Live codes.** Each account shows its current code and a countdown; click to copy.
- **`sesame` command.** `sesame github` prints the current code for the matching account.

## Install

Download the latest zip from [Releases](https://github.com/colinbm/sesame/releases/latest), unzip it, and move `Sesame.app` to Applications. The app is signed and notarized.

Requires macOS 14 or later, on Apple silicon or Intel.

The first scan asks for Screen Recording permission: allow Sesame under System Settings › Privacy & Security › Screen & System Audio Recording, then scan again.

## Command line tool

The tool ships inside the app. Choose **Install Command Line Tool…** from the **…** menu to copy a command that links it into `/usr/local/bin`, then paste that into a terminal.

```
sesame <name>               print the current code for the matching account
sesame list                 list accounts
sesame add <uri-or-image>   add an account from an otpauth:// URI or a QR code image file
sesame add <name> <key>     add an account from a base32 secret key
sesame remove <name>        remove the matching account
```

`<name>` matches the issuer, the account name or `issuer:name`, ignoring case. Failing an exact match, any unique substring will do. `-n` omits the trailing newline.

The first time the tool reads accounts added by the app (or the other way round), macOS asks for your login keychain password. Choose **Always Allow**.

### Entering codes automatically in iTerm

In Settings › Profiles › Advanced › Triggers, add a trigger:

| Field | Value |
| --- | --- |
| Regular expression | the prompt to react to, such as `Verification code:` |
| Action | Run Coprocess |
| Parameters | `/usr/local/bin/sesame github` |

The tool's output is typed into the session, and the trailing newline submits it.

## Where secrets are stored

Accounts live in a single item, "Sesame accounts", in your login keychain. They stay on this Mac: they are not synced through iCloud, so keep each site's recovery codes.

Only time-based (TOTP) codes are supported.

## Building

Open `Sesame.xcodeproj` in Xcode 27, or build from the command line:

```
xcodebuild -target Sesame -configuration Release build SYMROOT=build
```

Building the app also builds the `sesame` tool and embeds it at `Sesame.app/Contents/Helpers/sesame`. Set your own development team in the project's build settings to sign it.

The app icon is drawn by `Tools/make-icon.swift`.
