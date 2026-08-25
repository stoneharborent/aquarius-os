"""Unit tests for the decision engine (spec §5.1).

These use made-up probe dictionaries, so they run in milliseconds and never touch ffmpeg.
"""

from __future__ import annotations

import unittest

from aq_ingest import rules
from aq_ingest.config import Settings

FREE = Settings(resolve_edition="free")
STUDIO = Settings(resolve_edition="studio")


def video_stream(codec="h264", pix_fmt="yuv420p", r="25/1", avg="25/1", **extra):
    stream = {
        "codec_type": "video",
        "codec_name": codec,
        "pix_fmt": pix_fmt,
        "r_frame_rate": r,
        "avg_frame_rate": avg,
    }
    stream.update(extra)
    return stream


def audio_stream(codec="aac", **extra):
    stream = {"codec_type": "audio", "codec_name": codec}
    stream.update(extra)
    return stream


def probe(ext="mp4", streams=None, fmt=None, timing=None, identified=True):
    ffprobe = None
    if identified:
        ffprobe = {
            "format": fmt or {"format_name": "mov,mp4,m4a,3gp,3g2,mj2"},
            "streams": list(streams if streams is not None else [video_stream(), audio_stream()]),
        }
    return {
        "path": f"/cards/A001/CLIP.{ext}",
        "ext": ext,
        "ffprobe": ffprobe,
        "frame_timing": timing,
    }


class HelperTests(unittest.TestCase):
    def test_nearest_standard_rate(self):
        cases = {
            23.98: "24000/1001",
            24.0: "24/1",
            25.25: "25/1",
            29.9: "30000/1001",
            30.0: "30/1",
            48.0: "50/1",
            59.94: "60000/1001",
            61.0: "60/1",
        }
        for fps, expected in cases.items():
            with self.subTest(fps=fps):
                self.assertEqual(rules.nearest_standard_rate(fps), expected)

    def test_parse_rate(self):
        self.assertAlmostEqual(rules.parse_rate("30000/1001"), 29.97, places=2)
        self.assertIsNone(rules.parse_rate("0/0"))
        self.assertIsNone(rules.parse_rate(None))

    def test_bit_depth_from_pix_fmt_when_ffprobe_omits_it(self):
        self.assertEqual(rules.bit_depth({"pix_fmt": "yuv420p"}), 8)
        self.assertEqual(rules.bit_depth({"pix_fmt": "yuv420p10le"}), 10)
        self.assertEqual(rules.bit_depth({"pix_fmt": "yuv422p12le"}), 12)
        self.assertEqual(rules.bit_depth({"bits_per_raw_sample": "10"}), 10)

    def test_timecode_is_found_on_format_or_stream(self):
        self.assertEqual(
            rules.timecode_of({"format": {"tags": {"timecode": "01:00:00:00"}}, "streams": []}),
            "01:00:00:00",
        )
        self.assertEqual(
            rules.timecode_of(
                {"format": {}, "streams": [{"tags": {"timecode": "10:00:00;00"}}]}
            ),
            "10:00:00;00",
        )
        self.assertIsNone(rules.timecode_of({"format": {}, "streams": []}))


class PassThroughTests(unittest.TestCase):
    def test_prores_with_pcm_is_left_alone(self):
        plan = rules.decide(
            probe("mov", [video_stream("prores", "yuv422p10le"), audio_stream("pcm_s16le")]),
            FREE,
        )
        self.assertEqual(plan.action, rules.PASS_THROUGH)
        self.assertEqual(plan.rule, 1)

    def test_dnxhr_with_pcm_is_left_alone(self):
        plan = rules.decide(
            probe("mov", [video_stream("dnxhd", "yuv422p"), audio_stream("pcm_s16le")]), FREE
        )
        self.assertEqual(plan.action, rules.PASS_THROUGH)

    def test_camera_raw_is_never_probed_or_touched(self):
        for ext in ("braw", "r3d", "ari"):
            with self.subTest(ext=ext):
                plan = rules.decide(probe(ext, identified=False), FREE)
                self.assertEqual(plan.action, rules.PASS_THROUGH)

    def test_unreadable_mxf_is_assumed_to_be_a_camera_format(self):
        plan = rules.decide(probe("mxf", identified=False), FREE)
        self.assertEqual(plan.action, rules.PASS_THROUGH)

    def test_wav_is_left_alone(self):
        plan = rules.decide(
            probe("wav", [audio_stream("pcm_s16le")], fmt={"format_name": "wav"}), FREE
        )
        self.assertEqual(plan.action, rules.PASS_THROUGH)

    def test_png_is_left_alone(self):
        plan = rules.decide(
            probe("png", [video_stream("png", nb_frames="1")], fmt={"format_name": "png_pipe"}),
            FREE,
        )
        self.assertEqual(plan.action, rules.PASS_THROUGH)

    def test_studio_h264_with_pcm_is_already_ready(self):
        plan = rules.decide(probe("mov", [video_stream(), audio_stream("pcm_s16le")]), STUDIO)
        self.assertEqual(plan.action, rules.PASS_THROUGH)


class StillTests(unittest.TestCase):
    def test_heic_becomes_png_by_default(self):
        plan = rules.decide(probe("heic", identified=False), FREE)
        self.assertEqual(plan.action, rules.STILL_CONVERT)
        self.assertEqual(plan.output_suffix, ".png")
        self.assertEqual(plan.rule, 2)

    def test_heic_becomes_jpeg_when_configured(self):
        plan = rules.decide(
            probe("heif", identified=False), Settings(still_format="jpeg")
        )
        self.assertEqual(plan.output_suffix, ".jpg")


class TranscodeTests(unittest.TestCase):
    def test_free_resolve_transcodes_h264(self):
        plan = rules.decide(probe(), FREE)
        self.assertEqual(plan.action, rules.TRANSCODE)
        self.assertEqual(plan.rule, 5)
        self.assertEqual(plan.dnxhr_profile, "dnxhr_sq")
        self.assertEqual(plan.pix_fmt, "yuv422p")
        self.assertEqual(plan.output_suffix, ".mov")

    def test_ten_bit_source_uses_hqx(self):
        plan = rules.decide(
            probe("mp4", [video_stream("hevc", "yuv420p10le"), audio_stream()]), FREE
        )
        self.assertEqual(plan.dnxhr_profile, "dnxhr_hqx")
        self.assertEqual(plan.pix_fmt, "yuv422p10le")

    def test_profile_can_be_forced_by_config(self):
        plan = rules.decide(probe(), Settings(dnxhr_profile="hq"))
        self.assertEqual(plan.dnxhr_profile, "dnxhr_hq")
        self.assertEqual(plan.pix_fmt, "yuv422p")

    def test_vp9_is_transcoded_even_for_studio(self):
        plan = rules.decide(
            probe("webm", [video_stream("vp9"), audio_stream("opus")]), STUDIO
        )
        self.assertEqual(plan.action, rules.TRANSCODE)
        self.assertEqual(plan.rule, 4)

    def test_vfr_is_conformed_to_the_nearest_standard_rate(self):
        plan = rules.decide(
            probe(
                "mp4",
                [video_stream(r="50/1", avg="2500/99"), audio_stream()],
                timing={"deltas_vary": True, "sampled": 100},
            ),
            STUDIO,
        )
        self.assertEqual(plan.action, rules.TRANSCODE)
        self.assertEqual(plan.rule, 3)
        self.assertEqual(plan.conform_fps, "25/1")
        self.assertIn("vfr-conformed", plan.flags)

    def test_uneven_rates_with_steady_timing_are_not_vfr(self):
        job = probe(
            "mp4",
            [video_stream(r="50/1", avg="2500/99"), audio_stream()],
            timing={"deltas_vary": False, "sampled": 100},
        )
        self.assertTrue(rules.needs_frame_timing_scan(job))
        self.assertFalse(rules.is_vfr(job))
        self.assertEqual(rules.decide(job, STUDIO).action, rules.REWRAP)

    def test_matching_rates_never_trigger_a_timing_scan(self):
        self.assertFalse(rules.needs_frame_timing_scan(probe()))


class RewrapTests(unittest.TestCase):
    def test_studio_h264_with_aac_is_rewrapped(self):
        plan = rules.decide(probe(), STUDIO)
        self.assertEqual(plan.action, rules.REWRAP)
        self.assertEqual(plan.rule, 6)
        self.assertEqual(plan.output_suffix, ".mov")

    def test_ac3_and_dts_count_as_silent_audio(self):
        for codec in ("ac3", "eac3", "dts", "truehd"):
            with self.subTest(codec=codec):
                plan = rules.decide(
                    probe("ts", [video_stream(), audio_stream(codec)]), STUDIO
                )
                self.assertEqual(plan.action, rules.REWRAP)

    def test_prores_with_aac_gets_its_sound_fixed(self):
        # Resolved ambiguity: row 1 only means "leave alone" when the SOUND is fine too.
        plan = rules.decide(
            probe("mov", [video_stream("prores"), audio_stream("aac")]), FREE
        )
        self.assertEqual(plan.action, rules.REWRAP)

    def test_silent_mp4_is_repacked_but_silent_mov_is_not(self):
        self.assertEqual(
            rules.decide(probe("mp4", [video_stream()]), STUDIO).action, rules.REWRAP
        )
        self.assertEqual(
            rules.decide(probe("mov", [video_stream("prores")]), FREE).action,
            rules.PASS_THROUGH,
        )

    def test_audio_only_aac_becomes_a_wav(self):
        plan = rules.decide(probe("m4a", [audio_stream("aac")]), FREE)
        self.assertEqual(plan.action, rules.REWRAP)
        self.assertEqual(plan.output_suffix, ".wav")


class LeaveAloneTests(unittest.TestCase):
    def test_av1_is_reported_not_transcoded(self):
        plan = rules.decide(probe("mp4", [video_stream("av1"), audio_stream()]), FREE)
        self.assertEqual(plan.action, rules.LEAVE_ALONE)
        self.assertEqual(plan.rule, 7)
        self.assertIn("--force-transcode", plan.reason)

    def test_unknown_codec_is_never_guessed_at(self):
        plan = rules.decide(probe("mkv", [video_stream("theora"), audio_stream("vorbis")]), FREE)
        self.assertEqual(plan.action, rules.LEAVE_ALONE)
        self.assertEqual(plan.rule, 8)

    def test_a_file_ffprobe_cannot_read_is_left_alone(self):
        plan = rules.decide(probe("txt", identified=False), FREE)
        self.assertEqual(plan.action, rules.LEAVE_ALONE)


class ForceTranscodeTests(unittest.TestCase):
    def test_it_upgrades_a_rewrap(self):
        plan = rules.decide(probe(), STUDIO, force_transcode=True)
        self.assertEqual(plan.action, rules.TRANSCODE)

    def test_it_upgrades_av1(self):
        plan = rules.decide(
            probe("mp4", [video_stream("av1"), audio_stream()]), FREE, force_transcode=True
        )
        self.assertEqual(plan.action, rules.TRANSCODE)

    def test_it_leaves_photos_and_audio_alone(self):
        still = rules.decide(probe("png", [video_stream("png")]), FREE, force_transcode=True)
        self.assertEqual(still.action, rules.PASS_THROUGH)
        audio = rules.decide(
            probe("wav", [audio_stream("pcm_s16le")]), FREE, force_transcode=True
        )
        self.assertEqual(audio.action, rules.PASS_THROUGH)

    def test_it_leaves_camera_raw_alone(self):
        plan = rules.decide(probe("braw", identified=False), FREE, force_transcode=True)
        self.assertEqual(plan.action, rules.PASS_THROUGH)

    def test_it_still_conforms_a_vfr_clip(self):
        plan = rules.decide(
            probe(
                "mp4",
                [video_stream(r="50/1", avg="2500/99"), audio_stream()],
                timing={"deltas_vary": True},
            ),
            STUDIO,
            force_transcode=True,
        )
        self.assertEqual(plan.conform_fps, "25/1")


if __name__ == "__main__":
    unittest.main()
