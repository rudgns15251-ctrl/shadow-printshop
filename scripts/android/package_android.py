"""Package 음영 인쇄소 for Android (APK for testing, AAB for Google Play).

Builds from the committed game at a Git ref, in a fresh folder, with the patched
4.7.1 engine and the Android templates built from the same source. Nothing is
installed or changed outside the output folder: editor settings, Godot user
data and temp files are isolated there.

  debug   : signed with the standard Android debug key (test installs only).
  release : signed with YOUR upload key. Pass it through the environment, never
            on the command line or in a file in this repository:
              GODOT_ANDROID_KEYSTORE_RELEASE_PATH, GODOT_ANDROID_KEYSTORE_RELEASE_USER,
              GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
            (scripts/android/make_upload_key.ps1 creates one.)

usage: package_android.py --out DIR [--mode debug|release] [--format apk|aab|both]
                          [--ref HEAD] [--version-code N] [--version-name X.Y.Z]
Writes the packages, android-evidence.json (hashes, manifest facts, signature
checks) and a log of every command.
"""
import argparse
import datetime
import hashlib
import io
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tarfile
import zipfile

REPO = pathlib.Path(__file__).resolve().parents[2]
DATA = REPO / ".data"
TOOLCHAIN = DATA / "android-toolchain"
TEMPLATES = DATA / "qualified-templates-android-20261021"
GODOT = REPO.parents[1] / ".data/engine-build-20261017/binaries/patched-gdscript-fix-20261021/godot.windows.editor.x86_64.exe"
GAME = "projects/first-game/game"
PACKAGE = "com.shadowprintshop.game"
TITLE = "음영 인쇄소"
# Android screenOrientation values: 6 sensorLandscape, 11 userLandscape (Godot's
# mapping of SCREEN_SENSOR_LANDSCAPE: follows the sensor unless rotation is locked).
LANDSCAPE = {"6", "11"}
NIGHT = "Color(0.113725, 0.141176, 0.188235, 1)"
DEBUG_KEY = {"user": "androiddebugkey", "password": "android"}  # Android's published debug-key values.


def sha256(path):
    with open(path, "rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


class Packager:
    def __init__(self, args):
        self.args = args
        self.out = pathlib.Path(args.out).resolve()
        self.jdk = next((TOOLCHAIN / "jdk17").iterdir())
        self.sdk = TOOLCHAIN / "sdk"
        self.build_tools = self.sdk / "build-tools/36.1.0"
        self.log = []
        self.evidence = {"package": PACKAGE, "mode": args.mode, "version_code": args.version_code,
                         "version_name": args.version_name, "engine": str(GODOT), "engine_sha256": sha256(GODOT),
                         "templates": {}, "outputs": {}, "checks": [],
                         "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat()}
        appdata = self.out / "isolated"
        self.env = dict(os.environ, JAVA_HOME=str(self.jdk), ANDROID_HOME=str(self.sdk), ANDROID_SDK_ROOT=str(self.sdk),
                        APPDATA=str(appdata), LOCALAPPDATA=str(appdata), TEMP=str(appdata / "tmp"), TMP=str(appdata / "tmp"),
                        PATH=str(self.jdk / "bin") + os.pathsep + os.environ["PATH"],
                        # A daemon would outlive this run's isolated temp folder and break the next build.
                        GRADLE_OPTS="-Dorg.gradle.daemon=false")
        for name in ["GODOT_ANDROID_KEYSTORE_DEBUG_PATH", "GODOT_ANDROID_KEYSTORE_DEBUG_USER", "GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD"]:
            self.env.pop(name, None)

    def run(self, name, command, cwd=None, timeout=1800, secret=(), extra_env=None):
        shown = [str(part) for part in command]
        result = subprocess.run(shown, cwd=cwd, env=dict(self.env, **(extra_env or {})), capture_output=True, text=True,
                                encoding="utf-8", errors="replace", timeout=timeout)
        text = result.stdout + result.stderr
        for value in secret:
            text = text.replace(value, "***")
        (self.out / "logs").mkdir(parents=True, exist_ok=True)
        (self.out / "logs" / (name + ".log")).write_text(" ".join(shown) + "\n\n" + text, encoding="utf-8")
        self.log.append({"name": name, "command": shown, "returncode": result.returncode})
        return result.returncode, text

    def check(self, name, ok, detail=""):
        self.evidence["checks"].append({"name": name, "pass": bool(ok), "detail": detail})
        print(("PASS " if ok else "FAIL ") + name + (": " + detail if detail and not ok else ""))
        return ok

    def prepare(self):
        if self.out.exists() and any(self.out.iterdir()):
            raise SystemExit("Output folder is not empty: " + str(self.out))
        (self.out / "isolated/tmp").mkdir(parents=True)
        if self.args.game:
            # Test builds from a working copy (not a release source).
            self.game = self.out / "src" / GAME
            shutil.copytree(self.args.game, self.game, ignore=shutil.ignore_patterns(".godot", ".git"))
            self.evidence["source_commit"] = None
            self.evidence["source_folder"] = str(pathlib.Path(self.args.game).resolve())
        else:
            self.archive()
        for name in ["android_debug.apk", "android_release.apk", "android_source.zip"]:
            self.evidence["templates"][name] = sha256(TEMPLATES / name)
        expected = dict(line.split()[::-1] for line in (TEMPLATES / "SHA256SUMS.txt").read_text().splitlines() if line.strip())
        for name, digest in self.evidence["templates"].items():
            if expected.get(name, expected.get("*" + name)) != digest:
                raise SystemExit("Template hash differs from SHA256SUMS.txt: " + name)

    def archive(self):
        # The committed game, byte for byte (no line-ending conversion).
        commit = subprocess.check_output(["git", "-C", str(REPO), "rev-parse", self.args.ref], text=True).strip()
        archive = subprocess.check_output(["git", "-C", str(REPO), "-c", "core.autocrlf=false", "archive",
                                           "--format=tar", commit, GAME])
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(self.out / "src", filter="data")
        self.game = self.out / "src" / GAME
        self.evidence["source_commit"] = commit

    def keystore(self):
        if self.args.mode == "debug":
            path = TOOLCHAIN / "debug.keystore"
            if not path.exists():
                code, text = self.run("debug-keystore", [self.jdk / "bin/keytool.exe", "-genkeypair", "-keystore", path,
                                      "-storepass", DEBUG_KEY["password"], "-alias", DEBUG_KEY["user"], "-keypass",
                                      DEBUG_KEY["password"], "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000",
                                      "-dname", "CN=Android Debug,O=Android,C=US"])
                if code != 0:
                    raise SystemExit("Could not create the debug keystore")
            return str(path), DEBUG_KEY["user"], DEBUG_KEY["password"]
        names = ["GODOT_ANDROID_KEYSTORE_RELEASE_PATH", "GODOT_ANDROID_KEYSTORE_RELEASE_USER", "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD"]
        missing = [name for name in names if not os.environ.get(name)]
        if missing:
            raise SystemExit("Release signing needs your upload key in the environment: " + ", ".join(missing))
        path = pathlib.Path(os.environ[names[0]]).resolve()
        if REPO in path.parents:
            raise SystemExit("Keep the upload keystore outside the repository: " + str(path))
        return str(path), os.environ[names[1]], os.environ[names[2]]

    def presets(self, key_path, key_user):
        art = "res://assets/art/"
        sections = []
        for index, (name, gradle) in enumerate([("Android APK", False), ("Android AAB", True)]):
            options = {
                "custom_template/debug": (TEMPLATES / "android_debug.apk").as_posix(),
                "custom_template/release": (TEMPLATES / "android_release.apk").as_posix(),
                "gradle_build/use_gradle_build": gradle,
                "gradle_build/export_format": 1 if gradle else 0,
                "gradle_build/android_source_template": (TEMPLATES / "android_source.zip").as_posix() if gradle else "",
                "gradle_build/min_sdk": "24" if gradle else "",
                "gradle_build/target_sdk": "36" if gradle else "",
                "architectures/armeabi-v7a": False, "architectures/arm64-v8a": True,
                "architectures/x86": False, "architectures/x86_64": False,
                "version/code": self.args.version_code, "version/name": self.args.version_name,
                "package/unique_name": PACKAGE, "package/name": TITLE, "package/signed": True,
                "package/app_category": 2, "package/retain_data_on_uninstall": False,
                "launcher_icons/main_192x192": art + "app_icon.svg",
                "launcher_icons/adaptive_foreground_432x432": art + "android_icon_foreground.svg",
                "launcher_icons/adaptive_background_432x432": art + "android_icon_background.svg",
                "launcher_icons/adaptive_monochrome_432x432": art + "android_icon_monochrome.svg",
                "screen/immersive_mode": True,
                # The game's night colour from launch to the boot screen (UiTheme.NIGHT #1d2430);
                # the system splash shows the adaptive icon on it (Gradle builds apply the theme).
                "screen/background_color": NIGHT, "splash_screen/background_color": NIGHT,
                "user_data_backup/allow": False,
                # The game needs no permissions: no network, storage or sensors beyond rotation.
                "permissions/internet": False,
            }
            if self.args.mode == "debug":
                options.update({"keystore/debug": key_path, "keystore/debug_user": key_user})
            lines = ["[preset.%d]" % index, "", 'name="%s"' % name, 'platform="Android"', "runnable=%s" % ("false" if gradle else "true"),
                     "dedicated_server=false", 'custom_features=""', 'export_filter="all_resources"',
                     'include_filter="*.json,*.md"', 'exclude_filter="tests/*"', 'export_path=""',
                     'encryption_include_filters=""', 'encryption_exclude_filters=""', "encrypt_pck=false",
                     "encrypt_directory=false", "", "[preset.%d.options]" % index, ""]
            for option, value in options.items():
                if isinstance(value, bool):
                    value = "true" if value else "false"
                elif isinstance(value, str) and not value.startswith("Color("):
                    value = json.dumps(value, ensure_ascii=False)
                lines.append("%s=%s" % (option, value))
            sections.append("\n".join(lines))
        (self.game / "export_presets.cfg").write_text("\n\n".join(sections) + "\n", encoding="utf-8")
        settings = self.out / "isolated/Godot"
        settings.mkdir(parents=True, exist_ok=True)
        (settings / "editor_settings-4.7.tres").write_text(
            '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
            'export/android/java_sdk_path = "%s"\nexport/android/android_sdk_path = "%s"\n'
            % (self.jdk.as_posix(), self.sdk.as_posix()), encoding="utf-8")

    def export(self, key_path, key_user, key_password):
        flag = "--export-debug" if self.args.mode == "debug" else "--export-release"
        prefix = "DEBUG" if self.args.mode == "debug" else "RELEASE"
        self.env.update({"GODOT_ANDROID_KEYSTORE_%s_PATH" % prefix: key_path,
                         "GODOT_ANDROID_KEYSTORE_%s_USER" % prefix: key_user,
                         "GODOT_ANDROID_KEYSTORE_%s_PASSWORD" % prefix: key_password})
        secret = () if self.args.mode == "debug" else (key_password,)
        code, text = self.run("import", [GODOT, "--headless", "--path", self.game, "--import"], timeout=1200)
        self.check("project imports", code == 0, text[-2000:])
        stem = "shadowprintshop-%s-%s" % (self.args.version_name, self.args.mode)
        if self.args.format in ("apk", "both"):
            apk = self.out / (stem + ".apk")
            code, text = self.run("export-apk", [GODOT, "--headless", "--path", self.game, flag, "Android APK", apk], secret=secret)
            self.check("APK exported", code == 0 and apk.exists(), text[-3000:])
            if apk.exists():
                self.evidence["outputs"]["apk"] = {"file": apk.name, "bytes": apk.stat().st_size, "sha256": sha256(apk)}
                self.validate_apk(apk)
        if self.args.format in ("aab", "both"):
            aab = self.out / (stem + ".aab")
            code, text = self.run("export-aab", [GODOT, "--headless", "--path", self.game, "--install-android-build-template",
                                  flag, "Android AAB", aab], timeout=3600, secret=secret)
            self.check("AAB exported (Gradle build)", code == 0 and aab.exists(), text[-3000:])
            if aab.exists():
                self.evidence["outputs"]["aab"] = {"file": aab.name, "bytes": aab.stat().st_size, "sha256": sha256(aab)}
                self.validate_aab(aab)

    def manifest_facts(self, badging, label):
        facts = {}
        match = re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging)
        if match:
            facts.update(package=match.group(1), version_code=int(match.group(2)), version_name=match.group(3))
        for key, pattern in {"min_sdk": r"(?:minSdkVersion|sdkVersion):'(\d+)'", "target_sdk": r"targetSdkVersion:'(\d+)'"}.items():
            found = re.search(pattern, badging)
            facts[key] = int(found.group(1)) if found else None
        facts["permissions"] = sorted(set(re.findall(r"uses-permission: name='([^']+)'", badging)))
        facts["native_code"] = re.findall(r"native-code: (.*)", badging)
        self.evidence[label] = facts
        self.check(label + ": package, version and SDK levels",
                   facts.get("package") == PACKAGE and facts.get("version_code") == self.args.version_code
                   and facts.get("version_name") == self.args.version_name and facts.get("min_sdk") == 24
                   and facts.get("target_sdk") == 36, json.dumps(facts))
        self.check(label + ": 64-bit ARM code only", facts["native_code"] == ["'arm64-v8a'"], str(facts["native_code"]))
        # Godot's own manifest entries; nothing that reads data, the network or the camera.
        allowed = {PACKAGE + ".DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"}
        self.check(label + ": no runtime permissions", set(facts["permissions"]) <= allowed, str(facts["permissions"]))

    def validate_apk(self, apk):
        code, text = self.run("apksigner-apk", [self.build_tools / "apksigner.bat", "verify", "--verbose", "--print-certs", apk])
        self.check("APK signature verifies (v2+)", code == 0 and re.search(r"v2 scheme \(APK Signature Scheme v2\): true", text) is not None, text[-1500:])
        self.evidence["apk_signer"] = re.findall(r"Signer #1 certificate SHA-256 digest: ([0-9a-f]+)", text)
        code, text = self.run("aapt2-badging", [self.build_tools / "aapt2.exe", "dump", "badging", apk])
        self.check("APK manifest readable", code == 0, text[-1500:])
        self.manifest_facts(text, "apk_manifest")
        tree = self.run("aapt2-xmltree", [self.build_tools / "aapt2.exe", "dump", "xmltree", "--file", "AndroidManifest.xml", apk])[1]
        orientation = re.search(r"screenOrientation\(0x[0-9a-f]+\)=(\d+)", tree)
        self.check("APK: landscape that follows the phone's rotation", orientation is not None and orientation.group(1) in LANDSCAPE,
                   orientation.group(0) if orientation else "no screenOrientation")
        # Godot launches through an activity-alias, which aapt2 badging does not list.
        self.check("APK: launcher entry", "android.intent.category.LAUNCHER" in tree)
        with zipfile.ZipFile(apk) as archive:
            names = archive.namelist()
        self.check("APK: adaptive and monochrome launcher icons", any("mipmap-anydpi" in n for n in names)
                   and any("icon_monochrome" in n for n in names), "")

    def bundletool(self):
        jars = sorted(pathlib.Path.home().glob(".gradle/caches/modules-2/files-2.1/com.android.tools.build/bundletool/*/*/bundletool-*.jar"))
        if not jars:
            return None
        # The jar Gradle already downloaded for the AAB build, with its dependencies from the same cache.
        cache = pathlib.Path.home() / ".gradle/caches/modules-2/files-2.1"
        wanted = ["com.google.guava/guava", "com.google.protobuf/protobuf-java", "com.google.protobuf/protobuf-java-util",
                  "com.android.tools.build/aapt2-proto", "com.google.code.gson/gson", "com.google.dagger/dagger",
                  "javax.inject/javax.inject", "com.google.auto.value/auto-value-annotations", "org.bitbucket.b_c/jose4j",
                  "com.google.guava/failureaccess", "org.slf4j/slf4j-api", "com.android.tools.build/apksig",
                  "com.google.errorprone/error_prone_annotations", "com.google.j2objc/j2objc-annotations"]
        path = [str(jars[-1])]
        for group in wanted:
            owner, artifact = group.split("/")
            found = sorted((cache / owner / artifact).glob("*/*/*.jar"))
            found = [jar for jar in found if not jar.name.endswith(("-sources.jar", "-javadoc.jar"))]
            if found:
                path.append(str(found[-1]))
        return os.pathsep.join(path)

    def validate_aab(self, aab):
        code, text = self.run("jarsigner-aab", [self.jdk / "bin/jarsigner.exe", "-verify", "-verbose", "-certs", aab])
        signed = code == 0 and "jar verified" in text
        self.evidence["aab_signed"] = signed
        if self.args.mode == "release":
            # Google Play takes the bundle signed with the upload key.
            self.check("AAB is signed with the upload key (jar signature verifies)", signed, text[-1500:])
        classpath = self.bundletool()
        if not self.check("bundletool available from the Gradle cache", classpath is not None):
            return
        tool = [self.jdk / "bin/java.exe", "-cp", classpath, "com.android.tools.build.bundletool.BundleToolMain"]
        code, text = self.run("bundletool-validate", tool + ["validate", "--bundle=" + str(aab)])
        self.check("AAB passes bundletool validate", code == 0, text[-2000:])
        code, text = self.run("bundletool-manifest", tool + ["dump", "manifest", "--bundle=" + str(aab)])
        orientation = re.search(r'android:screenOrientation="(\d+)"', text)
        self.check("AAB manifest: package and landscape", 'package="%s"' % PACKAGE in text
                   and orientation is not None and orientation.group(1) in LANDSCAPE, text[-1500:])
        self.check("AAB manifest: launcher entry", "android.intent.category.LAUNCHER" in text)
        self.check("AAB manifest: version", 'android:versionCode="%d"' % self.args.version_code in text
                   and 'android:versionName="%s"' % self.args.version_name in text, "")
        self.check("AAB manifest: target SDK 36", 'android:targetSdkVersion="36"' in text, "")
        apks = self.out / (aab.stem + "-universal.apks")
        # What Play would serve, as one APK set signed with the same key (for a test install).
        key_path, key_user, key_password = self.keystore()
        secret = () if self.args.mode == "debug" else (key_password,)
        # The password goes through a file in the isolated folder (removed at the end), not the command line.
        password_file = self.out / "isolated" / "key-pass.txt"
        password_file.write_text(key_password, encoding="utf-8")
        try:
            code, text = self.run("bundletool-build-apks", tool + ["build-apks", "--bundle=" + str(aab), "--output=" + str(apks),
                                  "--mode=universal", "--aapt2=" + str(self.build_tools / "aapt2.exe"), "--ks=" + key_path,
                                  "--ks-key-alias=" + key_user, "--ks-pass=file:" + str(password_file),
                                  "--key-pass=file:" + str(password_file)], secret=secret)
        finally:
            password_file.unlink()
        self.check("AAB builds an installable universal APK set", code == 0 and apks.exists(), text[-2000:])
        if apks.exists():
            self.evidence["outputs"]["universal_apks"] = {"file": apks.name, "bytes": apks.stat().st_size, "sha256": sha256(apks)}

    def finish(self):
        self.evidence["finished_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        self.evidence["commands"] = self.log
        self.evidence["passed"] = all(item["pass"] for item in self.evidence["checks"])
        (self.out / "android-evidence.json").write_text(json.dumps(self.evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        sums = ["%s  %s" % (item["sha256"], item["file"]) for item in self.evidence["outputs"].values()]
        (self.out / "SHA256SUMS.txt").write_text("\n".join(sums) + "\n", encoding="utf-8")
        shutil.rmtree(self.out / "isolated", ignore_errors=True)
        print("ANDROID_PACKAGE_" + ("PASS" if self.evidence["passed"] else "FAIL"), self.out)
        return 0 if self.evidence["passed"] else 2


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", required=True)
    parser.add_argument("--mode", choices=["debug", "release"], default="debug")
    parser.add_argument("--format", choices=["apk", "aab", "both"], default="both")
    parser.add_argument("--ref", default="HEAD")
    parser.add_argument("--game", help="test build from this game folder instead of a commit")
    parser.add_argument("--version-code", type=int, default=1)
    parser.add_argument("--version-name", default="1.0.0")
    packager = Packager(parser.parse_args())
    packager.prepare()
    key = packager.keystore()
    packager.presets(key[0], key[1])
    packager.export(*key)
    return packager.finish()


if __name__ == "__main__":
    sys.exit(main())
