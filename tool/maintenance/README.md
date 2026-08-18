# Maintenance page

`index.html` here is a standalone maintenance notice for painterreference.com.

It lives outside `web/` on purpose. It must **not** be placed in `web/`, because
`web/index.html` is the Flutter web app's bootstrap page — overwriting it there
replaces the app's entry point, and `flutter build web` then produces a site
that never loads Flutter.

Firebase Hosting serves `build/web` (see `firebase.json`), so switching modes is
a matter of what sits in that directory at deploy time.

## Put the site into maintenance

```bash
cp tool/maintenance/index.html build/web/index.html
firebase deploy --only hosting
```

## Bring the live app back

```bash
flutter build web
firebase deploy --only hosting
```

`flutter build web` regenerates `build/web/index.html` from `web/index.html`,
which overwrites the maintenance copy — so no cleanup step is needed.
