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
                reference="ostree-unverified-registry:" + REF,
                layered=None, transaction=None):
    """A canned `rpm-ostree status --json`, shaped like the real one."""
    booted = {
        "booted": True,
        "staged": False,
        "version": version,
        "container-image-reference": reference,
        "container-image-reference-digest": digest,
        # The real answer always carries these lists, usually empty.
        "requested-packages": list(layered or []),
        "requested-local-packages": [],
        "requested-base-removals": [],
        "requested-base-local-replacements": [],
        "requested-local-fileoverride-packages": [],
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
    return json.dumps({"deployments": deployments, "transaction": transaction})


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


class LayeredAndBusyMachines(unittest.TestCase):
    """2026-10-21 bench: a machine with packages layered on top of the image, and
    an update service stuck behind a GNOME Software job."""

    def test_a_plain_machine_has_no_layers_and_is_not_busy(self):
        local = U["parse_local"](0, status_json())
        self.assertEqual(local["layered"], [])
        self.assertFalse(local["busy"])
        self.assertEqual(U["layered_advice"](local["layered"]), [])

    def test_layered_packages_are_named_and_explained(self):
        local = U["parse_local"](0, status_json(layered=["gnome-software-rpm-ostree", "rclone"]))
        self.assertEqual(local["layered"], ["gnome-software-rpm-ostree", "rclone"])
        advice = "\n".join(U["layered_advice"](local["layered"]))
        self.assertIn("gnome-software-rpm-ostree, rclone", advice)
        self.assertIn("rpm-ostree uninstall", advice)

    def test_layers_do_not_change_the_answer(self):
        # A layered machine can still be updated, so the state is unchanged.
        result = state_of(status_json(DIGEST_A, layered=["rclone"]), skopeo_json(DIGEST_B))
        self.assertEqual(result["state"], U["AVAILABLE"])
        self.assertEqual(result["layered"], ["rclone"])

    def test_a_running_job_is_busy(self):
        local = U["parse_local"](0, status_json(transaction=["upgrade", ":1.42", "/org/x"]))
        self.assertTrue(local["busy"])
        result = U["decide"](local, 0, skopeo_json(DIGEST_A), "")
        self.assertTrue(result["busy"])


class OneEngineOnePlace(unittest.TestCase):
    """GNOME Software is the one place updates come from; the terminal uses the
    same engine so the two never fight over the update lock."""

    def test_apply_uses_rpm_ostree_never_bootc(self):
        self.assertEqual(U["apply_command"](1000), ["pkexec", U["RPM_OSTREE"], "upgrade"])
        self.assertEqual(U["apply_command"](0), [U["RPM_OSTREE"], "upgrade"])
        self.assertNotIn("BOOTC", TARGET.read_text())

    def test_no_arguments_opens_software_not_our_window(self):
        calls = []
        g = U["main"].__globals__
        saved = (g["open_software"], g["gui"])
        g["open_software"] = lambda: calls.append("software") or 0
        g["gui"] = lambda: calls.append("window") or 0
        try:
            U["main"](["aquarius-updater"])
            U["main"](["aquarius-updater", "--gui"])
            U["main"](["aquarius-updater", "--window"])
        finally:
            g["open_software"], g["gui"] = saved
        self.assertEqual(calls, ["software", "software", "window"])

    def test_software_is_opened_on_its_updates_page(self):
        source = TARGET.read_text()
        self.assertIn('[GNOME_SOFTWARE, "--mode=updates"]', source)


class TheWordsPeopleRead(unittest.TestCase):
    def test_no_state_is_spelled_differently_in_two_places(self):
        self.assertEqual(
            sorted([U["UP_TO_DATE"], U["AVAILABLE"], U["RESTART_REQUIRED"],
                    U["OFFLINE"], U["UNKNOWN"]]),
            ["available", "offline", "restart-required", "unknown", "up-to-date"])

    def test_the_update_itself_still_asks_for_the_password_once(self):
        source = TARGET.read_text()
        self.assertIn('return ["pkexec", RPM_OSTREE, "upgrade"]', source)
        # ...and the check only reads: it never runs an upgrade.
        check = source.split("def check_update():", 1)[1].split("\ndef ", 1)[0]
        self.assertNotIn("apply_command", check)


if __name__ == "__main__":
    unittest.main(verbosity=2)
