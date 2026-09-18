# Google Play API / Fastlane

This project is prepared for a service-account JSON credential without committing it to source control.

Required environment variables:

- `PLAY_SERVICE_ACCOUNT_JSON`: local path to the downloaded service-account JSON file
- `PLAY_PACKAGE_NAME`: final Android application ID registered in Play Console
- `PLAY_VERIFY_TRACK`: optional read-only track for the authentication test, defaults to `internal`

Read-only authentication test:

```bash
bundle install
bundle exec fastlane android verify_play_api
```

Build only:

```bash
bundle exec fastlane android build_bundle
```

An internal-test upload lane exists but must only be run after the app exists in Play Console and the user has approved that upload. It creates a draft on the internal track and does not submit to production.

The service-account JSON must be retrieved from secure secret storage at runtime. Never copy the JSON into this repository, CI logs, chat, or an artifact archive.
