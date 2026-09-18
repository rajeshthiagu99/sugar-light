# Fresh personal Google Play account setup

## Proposed package identity

- Recommended final application ID: `com.rajesht.breatheagain`
- Subscription product ID: `breathe_again_monthly`
- Offer requirement: zero-price `P3D` phase, then ₹199/month

Why this package: it is name-derived, personal rather than tied to EpowerX Labs, short, and specific to Breathe Again. Package-name eligibility must still be checked and registered in Play Console before changing the Android project. Once an app is created with an application ID, treat that ID as permanent.

## Account-owner steps

1. Create a new **Personal** Play Console developer account under the Google account the user chooses.
2. Accept the Developer Distribution Agreement.
3. Pay the one-time US$25 registration fee only after the user sees and confirms the final checkout.
4. Complete identity/contact verification. Google may request government ID and a card in the same legal name.
5. Verify a non-rooted physical Android 10+ device through the Play Console mobile app as the account owner.
6. Register/check eligibility for `com.rajesht.breatheagain`, then create the app.

## New-personal-account launch constraint

A personal account created after November 13, 2023 must run a closed test with at least 12 testers continuously opted in for 14 days before it can apply for production access. Production access review usually takes up to 7 days but can take longer. Start tester recruitment before the app setup is complete so the test can begin as soon as the first AAB is ready.

## Service account and Fastlane

After account and app creation:

1. Create a Google Cloud project dedicated to this personal Play account.
2. Enable the Google Play Android Developer API.
3. Create a narrowly named service account for release automation.
4. Invite/link its email in Play Console Users and permissions.
5. Grant only the app-level permissions needed for release management and subscription/order access. Avoid account-admin permission.
6. Create one JSON key, move it directly to secure secret storage, and remove any downloaded plaintext copy after verification.
7. Set runtime variables `PLAY_SERVICE_ACCOUNT_JSON` and `PLAY_PACKAGE_NAME=com.rajesht.breatheagain`.
8. Run the prepared read-only check: `bundle exec fastlane android verify_play_api`.
9. Only after authentication succeeds and the final application ID is approved, migrate the Android namespace/source path, backend package constant and subscription-management deep link.
10. Internal-track upload remains a separate user-approved step. Production submission is never automated by the prepared lanes.

## Current preparation

The repository already contains `Gemfile`, `fastlane/Appfile`, `fastlane/Fastfile`, secret-safe `.gitignore` entries and a read-only authentication lane. No account, key, app or paid registration has been created yet.

## Official sources

- Account registration and fee: https://support.google.com/googleplay/android-developer/answer/6112435
- Personal-account closed testing: https://support.google.com/googleplay/android-developer/answer/14151465
- Device verification: https://support.google.com/googleplay/android-developer/answer/14316361
- Package-name registration: https://support.google.com/googleplay/android-developer/answer/16984799
