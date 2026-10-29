# Developing this fork alongside installed cmux

Use a fixed `jmin` build tag so the app is named `cmux DEV jmin`, with bundle ID
`com.cmuxterm.app.debug.jmin` and control socket `/tmp/cmux-debug-jmin.sock`.

After the prerequisites and setup in [CONTRIBUTING.md](../CONTRIBUTING.md):

```sh
./scripts/dev-jmin.sh --launch
./scripts/cli-jmin.sh settings path --json
```

For a build without launching, omit `--launch`. To validate compilation without
replacing the running development build, use `./scripts/dev-jmin.sh --build-only`.
The wrapper uses the local development backend; cloud features need their own
backend setup. A launch with this unoverridden local backend does not require an
upstream personal credential file. Explicit `--auth-profile`, `--credentials-file`
or `--expected-account` options still validate their requested identity. Remote
backend/API overrides and `--prod-auth` keep the authenticated launch requirement.
This changes only the local build script's startup prerequisite; production and
cloud server authentication remain unchanged. Tagged launch environments discard
inherited account, profile and credential variables.
Use the tagged CLI wrapper for development app commands.

## Settings isolation

| Data | Development location |
| --- | --- |
| JSON settings and saved layouts | `~/.config/cmux-dev/jmin/cmux.json` |
| Legacy JSON settings fallback | `~/.config/cmux-dev/jmin/settings.json` |
| Global Dock configuration | `~/.config/cmux-dev/jmin/dock.json` |
| Custom sidebars | `~/.config/cmux-dev/jmin/sidebars/` |
| Socket password and settings secrets | `~/.config/cmux-dev/jmin/` |
| cmux-managed Ghostty settings | `~/Library/Application Support/com.cmuxterm.app.debug.jmin/config.ghostty` |

Missing development settings start from defaults. The app does not import the
stable JSON settings, cmux-managed Ghostty config, or legacy socket password.
The native bundle identity wins over inherited shell context; standalone CLI
commands and the settings helper use `CMUX_BUNDLE_ID` supplied by the tagged app.
The installed stable app keeps its original locations.

Project configuration (`.cmux/cmux.json`, `.cmux/dock.json`) and standalone Ghostty
configuration (`~/.config/ghostty/`) remain shared inputs. This is settings
isolation, not a sandbox for filesystem access, cloud accounts or agent tools.

## Development icon

The development catalog uses a downward `V`, made by rotating the existing
`web/public/cmux-icon.svg` chevron 90 degrees clockwise. The editable source is
`design/jmin-dev-icon.svg`; the orange `DEV` banner stays upright. The running app
and Dock plugin also use downward light/dark appearance images. These repository
assets do not replace the installed stable app's icon.

To regenerate its ten catalog sizes and two appearance images with Node.js and `sharp` available:

```sh
node scripts/generate-jmin-dev-icon.cjs
```

## Verification

```sh
python3 tests/test_dev_config_isolation.py
python3 tests/test_reload_local_backend_auth.py
swift test --package-path Packages/macOS/CMUXAgentLaunch --filter AgentExternalLauncherTests
swift test --package-path Packages/macOS/CmuxSettings --filter CmuxConfigLocationTests
python3 scripts/verify-local.py --swift-changed
```

The portable probe compiles the production Swift path and password-store code,
then tests writes in temporary directories. The settings package tests also
exercise `JSONConfigStore`; the default Swift build engine requires Xcode's
string-catalog compiler.
An app build and live side-by-side check require full Xcode, not just Command Line Tools.

On a Command Line Tools-only Mac, the focused package tests can use the native
build engine with the installed Swift Testing framework and macro plugin:

```sh
swift test --build-system native --package-path Packages/macOS/CmuxSettings \
  -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  --filter 'CmuxConfigLocationTests|SocketControlPasswordStoreTests'
```

Use the same flags with `Packages/macOS/CMUXAgentLaunch` and
`--filter AgentExternalLauncherTests` for the external-launcher checks.

To undo this implementation, revert the code changes. Development files remain
in their separate directories and are not migrated back into the installed app.
