#!/usr/bin/env python3
"""Hand a freshly uploaded build to the external testers.

`altool --upload-app` finishes when App Store Connect has the file, and that is all it does. The
build then sits at READY_FOR_BETA_SUBMISSION until somebody opens the website and submits it, so
every release since the pipeline was written has uploaded a build that external testers never saw:
they were still on whichever build a person last submitted by hand.

Only a deliberate release comes through here. An automatic per-merge build is a prerelease in the
same sense the GitHub release is -- uploading it is useful, spending one of Apple's review slots on
it a dozen times a day is not.
"""
import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import jwt

API = "https://api.appstoreconnect.apple.com/v1"
# Apple rejects a token older than 20 minutes; processing can outlast one, so it is minted per call.
TOKEN_LIFETIME = 15 * 60


class Failure(RuntimeError):
    pass


def token(key_id: str, issuer_id: str, key_path: Path) -> str:
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer_id, "iat": now, "exp": now + TOKEN_LIFETIME, "aud": "appstoreconnect-v1"},
        key_path.read_text(),
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def request(method: str, path: str, auth: str, body: dict | None = None) -> dict:
    url = path if path.startswith("http") else f"{API}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {auth}")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            payload = response.read()
            return json.loads(payload) if payload else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise Failure(f"{method} {url} -> {error.code}\n{detail}") from None


def find_build(auth: str, app_id: str, version: str) -> dict:
    """The build with this exact CFBundleVersion, or a clear failure naming what is there instead."""
    page = request("GET", f"/builds?filter[app]={app_id}&filter[version]={version}&limit=10", auth)
    for build in page.get("data", []):
        if build["attributes"]["version"] == version:
            return build
    recent = request("GET", f"/builds?filter[app]={app_id}&sort=-uploadedDate&limit=5", auth)
    names = ", ".join(b["attributes"]["version"] for b in recent.get("data", []))
    raise Failure(f"No build {version} for app {app_id}. Most recent: {names or 'none'}")


def await_processing(auth: str, build_id: str, timeout: int) -> None:
    """Apple refuses to distribute a build it is still processing, and processing is minutes long."""
    deadline = time.time() + timeout
    seen = ""
    while time.time() < deadline:
        state = request("GET", f"/builds/{build_id}", auth)["data"]["attributes"]["processingState"]
        if state != seen:
            print(f"processing: {state}", flush=True)
            seen = state
        if state == "VALID":
            return
        if state in {"INVALID", "FAILED"}:
            raise Failure(f"Build {build_id} finished processing as {state}")
        time.sleep(30)
    raise Failure(f"Build {build_id} was still {seen or 'processing'} after {timeout}s")


def group_id(auth: str, app_id: str, name: str) -> str:
    page = request("GET", f"/betaGroups?filter[app]={app_id}&limit=50", auth)
    for group in page.get("data", []):
        if group["attributes"]["name"] == name:
            return group["id"]
    names = ", ".join(g["attributes"]["name"] for g in page.get("data", []))
    raise Failure(f"No beta group named {name!r}. Groups: {names or 'none'}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True)
    parser.add_argument("--build-version", required=True, help="CFBundleVersion of the upload")
    parser.add_argument("--group", required=True, help="External beta group to distribute to")
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer-id", required=True)
    parser.add_argument("--key-path", required=True, type=Path)
    parser.add_argument("--processing-timeout", type=int, default=45 * 60)
    arguments = parser.parse_args()

    credentials = (arguments.key_id, arguments.issuer_id, arguments.key_path)
    auth = token(*credentials)
    build = find_build(auth, arguments.app, arguments.build_version)
    print(f"build {arguments.build_version} is {build['id']}", flush=True)

    await_processing(token(*credentials), build["id"], arguments.processing_timeout)

    auth = token(*credentials)
    group = group_id(auth, arguments.app, arguments.group)
    request("POST", f"/betaGroups/{group}/relationships/builds", auth,
            {"data": [{"type": "builds", "id": build["id"]}]})
    print(f"added to beta group {arguments.group}", flush=True)

    # Already submitted is the state we want, not a failure: a rerun of a published release should
    # not turn red for finding its own work done.
    try:
        request("POST", "/betaAppReviewSubmissions", auth,
                {"data": {"type": "betaAppReviewSubmissions",
                          "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}}}})
    except Failure as error:
        if "ENTITY_ERROR" in str(error) or "already" in str(error).lower():
            print("already submitted for beta review", flush=True)
            return 0
        raise
    print("submitted for beta review", flush=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Failure as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
