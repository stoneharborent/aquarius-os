#!/usr/bin/python3
# =============================================================================
# test-updater.py — does the update check tell the truth?
# =============================================================================
# PLAIN ENGLISH
#
# The "Check for Update" window and `aq update check` decide what to tell you
# from two pieces of text: what this machine says it booted, and what the image
# store says it has published. This test feeds the decision canned copies of
# both — no network, no real system, no password — and checks it says the right
# thing every time.
#
# The one rule it exists to defend: an unreadable check is NEVER reported as
# "up to date", and a permission problem is NEVER reported as "no internet".
#
#   Run it:  python3 tests/test-updater.py
#            python3 tests/test-updater.py /usr/libexec/aquarius-updater
#
# The build runs it against the copy inside the finished image (77-updater.sh).
# =============================================================================
import json
import pathlib
import runpy
import sys
import unittest

DEFAULT = pathlib.Path(__file__).resolve().parents[1] / "system_files/usr/libexec/aquarius-updater"
TARGET = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
sys.argv = sys.argv[:1]

# The updater imports GTK only inside gui(), so loading it here is safe.
U = runpy.run_path(str(TARGET))

REF = "ghcr.io/stoneharborent/aquarius-os:latest"
DIGEST_A = "sha256:" + "a" * 64
DIGEST_B = "sha256:" + "b" * 64


def status_json(digest=DIGEST_A, version="20260913", staged=None,
                reference="ostree-unverified-registry:" + REF):
    """A canned `rpm-ostree status --json`, shaped like the real one."""
    booted = {
        "booted": True,
        "staged": False,
        "version": version,
        "container-image-reference": reference,
        "container-image-reference-digest": digest,
    }
    deployments = []
    if staged is not None:
        deployments.append({
            "booted": False,
            "staged": True,
            "version": staged,
            "container-image-reference": reference,
            "container-image-reference-digest": DIGEST_B,
        })
    deployments.append(booted)
    return json.dumps({"deployments": deployments})


def skopeo_json(digest=DIGEST_A, version="20260914"):
    """A canned `skopeo inspect`, cut down to the two fields we read."""
    return json.dumps({
        "Name": REF.split(":")[0],
        "Digest": digest,
        "Labels": {"org.opencontainers.image.version": version},
    })


def state_of(status_out, skopeo_out="", skopeo_code=0, skopeo_err="", status_code=0):
    local = U["parse_local"](status_code, status_out)
    return U["decide"](local, skopeo_code, skopeo_out, skopeo_err)


class ReadingThisMachine(unittest.TestCase):
    def test_reference_loses_its_transport_prefix(self):
        local = U["parse_local"](0, status_json())
        self.assertEqual(local["ref"], REF)
        self.assertEqual(local["digest"], DIGEST_A)
        self.assertEqual(local["version"], "20260913")
        self.assertFalse(local["staged"])

    def test_other_transport_spellings_are_handled(self):
        for prefix in ("ostree-unverified-image:docker://", "ostree-image-signed:docker://",
                       "docker://", "registry:"):
            local = U["parse_local"](0, status_json(reference=prefix + REF))
            self.assertEqual(local["ref"], REF, prefix)

    def test_malformed_json_is_unreadable(self):
        self.assertIsNone(U["parse_local"](0, "{not json at all"))
        self.assertIsNone(U["parse_local"](0, "[]"))
        self.assertIsNone(U["parse_local"](0, ""))

    def test_a_failed_command_is_unreadable(self):
        self.assertIsNone(U["parse_local"](1, status_json()))

    def test_no_booted_deployment_is_unreadable(self):
        self.assertIsNone(U["parse_local"](0, json.dumps({"deployments": [{"staged": True}]})))


class TheDecision(unittest.TestCase):
    def test_same_fingerprint_is_up_to_date(self):
        result = state_of(status_json(DIGEST_A), skopeo_json(DIGEST_A))
        self.assertEqual(result["state"], U["UP_TO_DATE"])
        self.assertEqual(result["current"], "20260913")

    def test_different_fingerprint_is_available_with_the_new_version(self):
        result = state_of(status_json(DIGEST_A), skopeo_json(DIGEST_B, "20260914"))
        self.assertEqual(result["state"], U["AVAILABLE"])
        self.assertEqual(result["version"], "20260914")
        self.assertEqual(result["current"], "20260913")

    def test_a_staged_update_asks_for_a_restart_and_never_touches_the_network(self):
        local = U["parse_local"](0, status_json(staged="20260914"))
        self.assertTrue(local["staged"])
        # No published answer given at all: the state must still be decided.
        result = U["decide"](local)
        self.assertEqual(result["state"], U["RESTART_REQUIRED"])
        self.assertEqual(result["version"], "20260914")

    def test_no_local_fingerprint_is_unknown_not_up_to_date(self):
        result = state_of(status_json(digest=""), skopeo_json(DIGEST_A))
        self.assertEqual(result["state"], U["UNKNOWN"])

    def test_unreadable_machine_is_unknown_not_up_to_date(self):
        result = U["decide"](None, 0, skopeo_json(DIGEST_A), "")
        self.assertEqual(result["state"], U["UNKNOWN"])


class WhenTheLookupFails(unittest.TestCase):
    def test_network_errors_are_offline(self):
        for message in ("dial tcp: lookup ghcr.io: no such host",
                        "Get \"https://ghcr.io/v2/\": net/http: TLS handshake timeout",
                        "connection refused",
                        "network is unreachable",
                        "i/o timeout"):
            result = state_of(status_json(), "", skopeo_code=1, skopeo_err=message)
            self.assertEqual(result["state"], U["OFFLINE"], message)

    def test_other_errors_are_unknown_never_offline_never_up_to_date(self):
        for message in ("This command must be executed as the root user",
                        "unauthorized: authentication required",
                        "manifest unknown",
                        "skopeo: command not found"):
            result = state_of(status_json(), "", skopeo_code=1, skopeo_err=message)
            self.assertEqual(result["state"], U["UNKNOWN"], message)

    def test_malformed_published_answer_is_unknown(self):
        for out in ("{broken", "[]", "", json.dumps({"Labels": {}})):
            result = state_of(status_json(), out)
            self.assertEqual(result["state"], U["UNKNOWN"], out)

    def test_a_missing_version_label_still_reports_an_update(self):
        out = json.dumps({"Digest": DIGEST_B, "Labels": {}})
        result = state_of(status_json(DIGEST_A), out)
        self.assertEqual(result["state"], U["AVAILABLE"])
        self.assertEqual(result["version"], "")


class TheWordsPeopleRead(unittest.TestCase):
    def test_no_state_is_spelled_differently_in_two_places(self):
        self.assertEqual(
            sorted([U["UP_TO_DATE"], U["AVAILABLE"], U["RESTART_REQUIRED"],
                    U["OFFLINE"], U["UNKNOWN"]]),
            ["available", "offline", "restart-required", "unknown", "up-to-date"])

    def test_the_update_itself_still_asks_for_the_password_once(self):
        source = TARGET.read_text()
        self.assertIn('["pkexec", BOOTC, "upgrade"]', source)
        # ...and the check does not run bootc at all any more.
        check = source.split("def check_update():", 1)[1].split("\ndef ", 1)[0]
        self.assertNotIn("BOOTC", check)


if __name__ == "__main__":
    unittest.main(verbosity=2)
