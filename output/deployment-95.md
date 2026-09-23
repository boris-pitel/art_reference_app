# Build 95 deployment

Commit: 9953c8137a62b8a104f2b6e6fb3364637d5b0bd1
Branch: codex/offline-release-93

- Windows: successfully built; FileVersion and ProductVersion 1.2.0+95.
- Android Firebase Testers: successfully uploaded 1.2.0 (95) and distributed to android-testers. Job https://codemagic.io/app/6a8df6095d07626d277128fb/build/6aa04345e3487c33c1c7368d
- iPhone: compiled successfully. Publishing job failed because Apple returned HTTP 500 CREATE BUILD, despite altool then reporting UPLOAD SUCCEEDED and delivery UUID 907bb711-4e69-4881-89b8-6fbf207e359d. Verify build 95 in TestFlight before retrying. Job https://codemagic.io/app/6a8df6095d07626d277128fb/build/6aa04304f2a6adcbe824f634
- App Store Connect browser requires user sign-in; verification blocked on authentication.

Eight offline regression tests and two version tests passed. Dart analysis passed.