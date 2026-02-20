# auto_l10n example

## Run immediately (no API key needed)

```
flutter run
```

Strings will appear in English, then update after 500ms with a globe prefix.
Hot restart to see instant loading from cache.

## Switch to DeepL

Replace `MockTranslator` in `main.dart`:

```dart
translator: DeepLTranslator(apiKey: 'YOUR_DEEPL_KEY'),
```

Free tier: https://www.deepl.com/pro#developer

## Switch to Google Translate

```dart
translator: GoogleTranslator(apiKey: 'YOUR_GOOGLE_KEY'),
```

## Use your own translator

Implement `AbstractTranslator` and pass it in.
