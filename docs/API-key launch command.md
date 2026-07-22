We are not connecting the UI yet, but this is how the key will later be supplied:
flutter run -d windows --dart-define=ALPHA_VANTAGE_API_KEY=YOUR_REAL_KEY
For Chrome preview:
flutter run -d chrome --dart-define=ALPHA_VANTAGE_API_KEY=YOUR_REAL_KEY
Do not commit the real key into Dart source code. A dart-define key is acceptable for a private local prototype, but it can still be discovered in a distributed client build—especially a web build. Before public release, we’ll move market-data calls behind a small backend proxy.
