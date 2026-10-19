# Normal release flow

Mobile updates are distributed over the air. Do not ask the user to attach a USB device for a normal release.

## Android

Use the existing Codemagic application https://codemagic.io/app/6a8df6095d07626d277128fb/settings and select the **Android Firebase Testers** workflow on the requested branch. Codemagic holds the release signing key, builds the signed Android release, uploads it to **Firebase App Distribution**, and distributes it to the **android-testers** group. Confirm the publishing log says the requested version/build was uploaded and distributed before reporting completion.

Evidence: output/deployment-95.md and docs/releases/1.2.2+102.md record successful builds and delivery through this channel; docs/releases/1.2.2+104.md records a later queued job.

This checkout has no android/key.properties. The Gradle configuration falls back to debug signing for a local release build without CI credentials or key.properties. A locally built APK must not be offered as the normal tester update without checking its signing identity against the existing distribution build.

tool/deploy/deploy-phone.ps1 is an older developer ADB-install helper, not the normal distribution workflow. tool/deploy/release-all.ps1 -Phone invokes that legacy helper and likewise does not distribute to testers.

## iPhone

Use Codemagic's existing iOS **Default Workflow**, which builds/signs the app and uploads to App Store Connect/TestFlight. Confirm Apple processing and tester availability separately from compilation. Public App Store submission is a separate action.

## Windows and web

Windows uses the local installer and existing app installation. Web uses Firebase Hosting. Unison remains hidden on web until the user requests otherwise.
