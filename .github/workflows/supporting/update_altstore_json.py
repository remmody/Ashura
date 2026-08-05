#!/usr/bin/env python3
"""Update AltStore/SideStore apps.json from Ashura GitHub Releases.

Prefers the floating `nightly` prerelease while stable releases are not the
primary distribution channel. Falls back to the newest non-draft release
(including prereleases) that has an .ipa asset.
"""

from __future__ import annotations

import io
import json
import os
import plistlib
import re
import zipfile
from datetime import datetime, timezone

import requests

BUNDLE_ID = "app.remmody.ashura"
MINIMUM_IOS_VERSION = "15.0"
JSON_FILE = ".github/workflows/supporting/altstore/apps.json"
GITHUB_REPO = os.environ.get("GITHUB_REPOSITORY", "remmody/Ashura")
PREFERRED_TAG = os.environ.get("ASHURA_RELEASE_TAG", "nightly")
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")


def _headers() -> dict[str, str]:
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if GITHUB_TOKEN:
        headers["Authorization"] = f"Bearer {GITHUB_TOKEN}"
    return headers


def fetch_release_by_tag(repo: str, tag: str) -> dict | None:
    url = f"https://api.github.com/repos/{repo}/releases/tags/{tag}"
    response = requests.get(url, headers=_headers(), timeout=60)
    if response.status_code == 404:
        return None
    response.raise_for_status()
    return response.json()


def fetch_latest_release_with_ipa(repo: str) -> dict:
    url = f"https://api.github.com/repos/{repo}/releases"
    response = requests.get(url, headers=_headers(), timeout=60)
    response.raise_for_status()
    releases = response.json()
    if not isinstance(releases, list) or not releases:
        raise ValueError("No releases found.")

    releases = [r for r in releases if not r.get("draft")]
    releases.sort(
        key=lambda r: datetime.strptime(r["published_at"], "%Y-%m-%dT%H:%M:%SZ"),
        reverse=True,
    )
    for release in releases:
        if any(a.get("name", "").endswith(".ipa") for a in release.get("assets", [])):
            return release
    raise ValueError("No release with an .ipa asset found.")


def pick_ipa_asset(release: dict) -> dict:
    assets = release.get("assets") or []
    # Prefer stable Ashura.ipa name used by nightly publishes.
    for asset in assets:
        if asset.get("name") == "Ashura.ipa":
            return asset
    for asset in assets:
        if asset.get("name", "").endswith(".ipa"):
            return asset
    raise ValueError(".ipa file is not found in release assets")


def remove_markup(text: str) -> str:
    text = re.sub(r"<[^<]+?>", "", text)
    text = re.sub(r"#{1,6}\s?", "", text)
    text = re.sub(r"\*{2}", "", text)
    text = re.sub(r"(?m)^-\s+", "• ", text)
    text = re.sub(r"`", '"', text)
    text = text.replace("\r\n", "\n")
    return text.strip()


def get_ipa_version_and_build(ipa_bytes: bytes) -> tuple[str, str]:
    with zipfile.ZipFile(io.BytesIO(ipa_bytes)) as ipa:
        info_plist_path = None
        for name in ipa.namelist():
            if (
                name.startswith("Payload/")
                and name.count("/") == 2
                and name.endswith(".app/Info.plist")
            ):
                info_plist_path = name
                break
        if not info_plist_path:
            raise FileNotFoundError("Info.plist not found in IPA")
        with ipa.open(info_plist_path) as plist_file:
            plist = plistlib.load(plist_file)
        version = plist.get("CFBundleShortVersionString")
        build = str(plist.get("CFBundleVersion"))
        if not version or not build:
            raise ValueError("IPA Info.plist missing version/build")
        return str(version), build


def resolve_release(repo: str) -> dict:
    preferred = fetch_release_by_tag(repo, PREFERRED_TAG)
    if preferred and any(
        a.get("name", "").endswith(".ipa") for a in preferred.get("assets", [])
    ):
        print(f"Using preferred release tag '{PREFERRED_TAG}'")
        return preferred
    print(f"Preferred tag '{PREFERRED_TAG}' missing/empty; falling back to latest IPA release")
    return fetch_latest_release_with_ipa(repo)


def update_json_file(json_file: str, repo: str) -> None:
    release = resolve_release(repo)
    with open(json_file, "r", encoding="utf-8") as file:
        data = json.load(file)

    apps = data.get("apps") or []
    if not apps:
        raise ValueError(f'There is no data for "apps" key in {json_file}.')

    app = apps[0]
    app.setdefault("versions", [])
    data["featuredApps"] = [BUNDLE_ID]
    app["bundleIdentifier"] = BUNDLE_ID
    app["tintColor"] = "B026FF"

    asset = pick_ipa_asset(release)
    download_url = asset["browser_download_url"]
    size = asset["size"]

    print(f"Downloading IPA from {download_url}")
    ipa_response = requests.get(download_url, headers=_headers(), timeout=300)
    ipa_response.raise_for_status()
    version, build = get_ipa_version_and_build(ipa_response.content)

    published = datetime.strptime(release["published_at"], "%Y-%m-%dT%H:%M:%SZ").replace(
        tzinfo=timezone.utc
    )
    version_date = published.strftime("%Y-%m-%d")
    tag = release.get("tag_name", "")
    sha = (release.get("target_commitish") or "")[:7]
    is_nightly = tag == "nightly" or release.get("prerelease") is True

    description = remove_markup(release.get("body") or "")
    if not description:
        description = (
            f"Nightly build {build}"
            if is_nightly
            else f"Release {tag or version}"
        )

    marketing = (
        f"Nightly ({sha or build})"
        if is_nightly
        else f"{version} ({build})"
    )

    version_entry = {
        "version": version,
        "date": version_date,
        "localizedDescription": description,
        "downloadURL": download_url,
        "size": size,
        "minOSVersion": MINIMUM_IOS_VERSION,
        "buildVersion": build,
        "marketingVersion": marketing,
    }

    # Nightlies: keep a short history keyed by buildVersion; stable: prepend if new.
    existing = app["versions"]
    existing = [v for v in existing if v.get("buildVersion") != build]
    if is_nightly:
        # Drop older nightlies beyond the newest few with same marketing channel.
        non_nightly = [
            v
            for v in existing
            if not str(v.get("marketingVersion", "")).startswith("Nightly")
        ]
        nightlies = [
            v
            for v in existing
            if str(v.get("marketingVersion", "")).startswith("Nightly")
        ][:4]
        app["versions"] = [version_entry] + nightlies + non_nightly
    else:
        app["versions"] = [version_entry] + existing

    # Keep sourceURL pointed at GitHub Pages.
    data["sourceURL"] = "https://remmody.github.io/Ashura/apps.json"
    data["identifier"] = "app.remmody.ashura.altstore"
    data["name"] = "Ashura Source"
    app["iconURL"] = "https://remmody.github.io/Ashura/icon.png"

    with open(json_file, "w", encoding="utf-8") as file:
        json.dump(data, file, indent=2)
        file.write("\n")
    print("JSON file updated successfully.")


def main() -> None:
    update_json_file(JSON_FILE, GITHUB_REPO)


if __name__ == "__main__":
    main()
