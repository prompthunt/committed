# Contributing to Committed

Focused bug fixes and documentation improvements are welcome. For features or
larger changes, open an issue to agree on the problem and scope before writing code.
Review capacity is limited; submitting a pull request does not guarantee acceptance.

## Build the Mac app

Use macOS 26 or later and Xcode 26 or later. Clone the public source:

```sh
git clone https://github.com/prompthunt/committed.git
cd committed
xcodebuild -scheme CommitStandings -configuration Debug \
  -destination 'platform=macOS' CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= build test
```

Xcode resolves Sparkle through Swift Package Manager. No Apple distribution
certificate, notarization credential, or GitHub token is required to build and run
the tests. The test host uses in-memory credentials and does not connect to GitHub.
Using the app's live board requires connecting your own GitHub account.

The checked-in `CommitStandings.xcodeproj` is ready to open in Xcode. Keep it at
the repository root. `project.yml` is the optional XcodeGen specification; it reads
the checked-in `Info.plist` and entitlements rather than generating replacements.
If you add Swift files, include them in the Xcode project and verify a build.

Local development uses a separate bundle ID from the distributed app. Preserve
that separation and the existing official bundle ID, Keychain service, and Sparkle
public key. See [AGENTS.md](AGENTS.md) for update compatibility requirements.

## Build the marketing site

```sh
cd site
# Use Node 22 (.nvmrc).
npm ci
npm run build
npm run typecheck
```

See [site/README.md](site/README.md) for the layout, demo data, and deployment notes.
For UI changes, include desktop/mobile screenshots and check keyboard access,
reduced motion, and readable text wrapping. Keep the existing design scope.

## Pull requests

Explain the problem, the change, and how you checked the affected behavior. Include
reproduction steps for bug fixes. Keep unrelated changes in separate pull requests.
Do not commit personal account data, access tokens, signing material, or build output.
Report security issues through [SECURITY.md](SECURITY.md), not a public issue.

## Official releases

Official releases remain in `prompthunt/commit-standings-releases`. Only maintainers
with the existing signing and notarization credentials publish them, using
`scripts/publish-release.sh`. See [docs/distribution.md](docs/distribution.md).
Public CI builds and tests without those credentials and does not publish releases.
For a distributed fork, use your own app identity, OAuth registration, signing keys,
and update feed. Do not publish a fork that points at Committed's official feed.

Contributions to the project source are under the [MIT license](LICENSE).
Third-party assets retain their own terms; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
