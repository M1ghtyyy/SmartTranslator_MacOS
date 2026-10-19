# SmartTranslator

A smart translator for macOS. Select text in any app, Force Click it on the trackpad, and the translation pops up right below the phrase.

It translates meaning, not words: idioms, phrasal verbs, slang and set expressions become their natural equivalents. "Break the ice" turns into the target language's idiom for it, not a word-for-word calque.

- **Works everywhere:** Safari, Chrome, Telegram, Notes, Mail, code editors and any other app.
- **Three ways to translate:** Force Click, the ⌃⌥T hotkey, or right-click → Services.
- **Free:** translations come from free models (Google Gemini, OpenRouter, Groq) or from a local model via Ollama that works offline.
- **Stays out of the way:** lives in the menu bar, and the translation popover never steals focus from the app you're working in.

## What it does

| You select | You get |
|---|---|
| A word — `ice` | The main translations, part of speech and an example |
| A phrase or idiom — `call it a day` | A meaning-based translation, plus the literal one when they differ a lot |
| A sentence or paragraph | A natural translation and a list of idioms with explanations |

If the text is already in your target language, it's translated into English instead (or into Russian when the target language is English).

## Requirements

- macOS 14 Sonoma or later.
- Force Click needs a Force Touch trackpad: MacBooks from roughly 2015–2018 onwards and Magic Trackpad 2 or later. With a mouse, use the hotkey or the Services menu.
- A free API key from one of the providers (see [Choosing a model](#choosing-a-model)) to translate online. Ollama needs no key.

## Installation

### Option 1. Download a release

1. Open **Releases** on the right side of the repository page and download `SmartTranslator.zip`.
2. Unzip it and move `SmartTranslator.app` to Applications or `~/Applications`.
3. The app isn't signed with an Apple Developer ID, so macOS blocks it on first launch. To allow it, either:
   - open System Settings → Privacy & Security, scroll down and click **Open Anyway** next to SmartTranslator;
   - or run this in Terminal (adjust the path):
     ```bash
     xattr -dr com.apple.quarantine /Applications/SmartTranslator.app
     ```

### Option 2. Build from source

You don't need Xcode, the Command Line Tools are enough.

1. Install the Command Line Tools if you don't have them:
   ```bash
   xcode-select --install
   ```
2. Download the source (green **Code → Download ZIP** button) or clone the repository, and open its folder in Terminal.
3. Create a signing certificate once. It keeps macOS from revoking the Accessibility permission after every rebuild:
   ```bash
   Scripts/create-dev-cert.sh
   ```
4. Build and install:
   ```bash
   Scripts/build-app.sh --install
   ```
   The script builds `SmartTranslator.app`, copies it to `~/Applications`, registers the Services menu item and launches the app.

## First launch

1. **Grant access.** On first launch macOS asks for Accessibility access — without it the app can't read the selected text. If the prompt didn't appear, go to System Settings → Privacy & Security → Accessibility and turn SmartTranslator on.
2. **Free up Force Click from the system dictionary.** Otherwise the macOS dictionary opens on top of the translation. Go to System Settings → Trackpad → Point & Click → Look up & data detectors and choose **Tap with Three Fingers**. The dictionary stays one three-finger tap away, and Force Click translates.
3. **Connect a model.** Click the SmartTranslator icon in the menu bar → Settings…. Pick a provider, paste your key and click **Test Translation**.

That's it: select some text and Force Click it.

## Usage

| Method | How |
|---|---|
| Force Click | Select text and press firmly on it with the trackpad |
| Hotkey | Select text and press **⌃⌥T** (configurable in Settings) |
| Context menu | Right-click the selection → Services → **Translate with SmartTranslator** |
| Menu bar | SmartTranslator icon → Translate Selection |
| URL | `smarttranslator://translate?text=Hello%20world` — for Shortcuts, Raycast, Alfred and scripts |

The translation popover:
- closes with **Esc**, the × button, or a click anywhere else;
- the copy button puts the translation on the clipboard as plain text;
- you can also select and copy parts of the translation by hand.

## Choosing a model

Pick the provider, model and key in Settings… → Model. Keys are stored in the macOS Keychain.

| Provider | Price | Get a key | Notes |
|---|---|---|---|
| **Google Gemini** (default) | Free | [aistudio.google.com/apikey](https://aistudio.google.com/apikey) | Daily request limit. Unavailable in some countries |
| **OpenRouter** | Free for `:free` models | [openrouter.ai/keys](https://openrouter.ai/keys) | Click Load Models and pick a model ending in `:free`. About 50 requests a day without credits |
| **Groq** | Free | [console.groq.com/keys](https://console.groq.com/keys) | Very fast, with per-minute and daily limits |
| **DeepSeek** | Paid, a fraction of a cent per translation | [platform.deepseek.com](https://platform.deepseek.com/api_keys) | Requires a top-up |
| **Ollama** | Free, offline | Not needed | The model runs on your Mac. Weaker on idioms than the cloud models |
| **Custom API** | — | — | Any service with an OpenAI-compatible `/chat/completions` endpoint |

If the default model doesn't respond or has been retired, click **Load Models** and pick another one.

**Setting up Ollama:**
```bash
brew install ollama
ollama serve            # unless the Ollama app is already running
ollama pull qwen2.5:7b
```
Then choose "Ollama (local, offline)" in Settings.

## Settings

- **Translate into** — the target language, Russian by default. Also available: English, Ukrainian, German, French, Spanish, Italian, Portuguese, Polish, Turkish, Chinese, Japanese and Korean.
- **Force Click on selected text** — turns Force Click translation on or off.
- **Suppress the system dictionary on Force Click** — an experimental alternative to the trackpad setting from [First launch](#first-launch). Off by default.
- **Hotkey** — ⌃⌥T, ⌥⌘T, ⌃⌘T, or off.
- **Verbose logging** — a detailed log for troubleshooting.

## Privacy

- The selected text is sent only to the provider you chose, and only when you ask for a translation. With Ollama the text never leaves your Mac.
- Some apps (browsers, Telegram) don't expose the selection directly. Then SmartTranslator presses ⌘C itself, reads the text and immediately restores what was on your clipboard. Clipboard managers (Paste, Maccy and others) may still catch the intermediate copy.
- The log at `~/Library/Logs/SmartTranslator.log` records service events and text lengths, never the text itself.

## Troubleshooting

**Force Click does nothing**
- In Settings… → Permissions, Accessibility should say "Granted".
- If you rebuilt the app without the certificate from the build steps, macOS treats it as a new app. Remove SmartTranslator from the Accessibility list with the "−" button and add it again.
- Check that Force Click is on: System Settings → Trackpad → Force Click and haptic feedback.
- Force Click only works on selected text.

**The system dictionary opens on top of the translation**
Set Look up & data detectors to Tap with Three Fingers (see [First launch](#first-launch)).

**"Free request limit reached" or "The service is temporarily unavailable"**
You've used up the free quota or the service is overloaded. Wait a bit, pick another model (Load Models) or switch providers.

**"The API key was rejected, or the service isn't available in your region"**
Check the key. If the service isn't available in your country, try OpenRouter, DeepSeek or Ollama.

**No item in the Services menu**
Enable it under System Settings → Keyboard → Keyboard Shortcuts → Services → Text → Translate with SmartTranslator. If it isn't listed there, restart the app.

**Need more details**
Turn on Verbose Logging in the menu bar menu, repeat what went wrong and open the log with Open Log.

## Uninstalling

1. Menu bar icon → Quit SmartTranslator.
2. Delete `SmartTranslator.app` from `~/Applications` or Applications.
3. Remove the app from System Settings → Privacy & Security → Accessibility.
4. To remove settings and keys:
   ```bash
   defaults delete com.vladimirbelaev.SmartTranslator
   security delete-generic-password -s com.vladimirbelaev.SmartTranslator.api-key   # repeat until it says "not found"
   ```
5. If you built from source, delete the "SmartTranslator Dev" certificate in Keychain Access.

## For developers

```bash
swift build                      # debug build
swift test                       # unit tests
Scripts/build-app.sh             # build build/SmartTranslator.app
Scripts/build-app.sh --install   # build, install to ~/Applications and launch
```

To publish a release build:
```bash
Scripts/build-app.sh
ditto -c -k --keepParent build/SmartTranslator.app SmartTranslator.zip
```

Layout:

```
Sources/SmartTranslatorCore/   prompt, streaming OpenAI-compatible client, provider presets
Sources/SmartTranslator/
  App/          launch, menu bar, trigger → selection → translation flow
  Trigger/      Force Click (CGEventTap), hotkey, Services
  Selection/    reading the selection: Accessibility, ⌘C fallback
  UI/           translation popover
  Settings/     settings and Keychain
Tests/          core tests (swift-testing)
Scripts/        .app bundling and the signing certificate
```
