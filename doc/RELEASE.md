# Release setup

flutter_connect follows the publishing pattern used by flutter_licensing, flutter_paytorl and flutter_txms. A version tag push runs the shared CI checks and exact tag/version validation, then publishes through Dart's reusable pub.dev workflow. It does not create or modify a GitHub Release.

1. Update `pubspec.yaml` and `CHANGELOG.md`, then commit and push the source and workflows.
2. On pub.dev, enable automated publishing for repository `bchainhub/flutter_connect` with tag pattern `{{version}}` (no `v`).
3. Push the tag matching the manifest:

```sh
git tag 0.1.2
git push origin 0.1.2
```

CI checks formatting, static analysis, tests, publishable package contents, and Android/iOS example builds before publication. A tag mismatch blocks publishing. Use a new version for each publication; an already published pub.dev version cannot be replaced.

The npm packages use a different trigger: publish their GitHub Releases in the app to publish npm. For Flutter, pushing the tag is sufficient. Merely editing an existing GitHub Release does not trigger the Flutter workflow.

CORE License remains unchanged. Dependency lockfiles and generated artifacts remain ignored.

See [Dart automated publishing](https://dart.dev/tools/pub/automated-publishing) for registry setup.
