"""
* This file is part of PYSLAM
*
* Copyright (C) 2016-present Luigi Freda <luigi dot freda at gmail dot com>
*
* PYSLAM is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* PYSLAM is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with PYSLAM. If not, see <http://www.gnu.org/licenses/>.
"""

"""Tests for BoreasDataset and BoreasGroundTruth on a tiny synthetic sequence."""

import contextlib
import io
import os
import tempfile
import unittest
from unittest import TestCase

import cv2
import numpy as np

from pyslam.io.dataset import BoreasDataset
from pyslam.io.dataset_types import DatasetType, SensorType
from pyslam.io.ground_truth import BoreasGroundTruth, boreas_rotation_enu_sensor
from pyslam.utilities.geometry import qvec2rotmat

kSequenceName = "boreas-test"
# image timestamps in microseconds; 10 Hz, with the second stem shorter to test numeric sorting
kImageStampsUs = [999999900000, 1000000000000, 1000000100000]
kCsvHeader = (
    "GPSTime,easting,northing,altitude,vel_east,vel_north,vel_up,"
    "roll,pitch,heading,angvel_z,angvel_y,angvel_x"
)


def write_sequence(root, csv_rows):
    seq = os.path.join(root, kSequenceName)
    os.makedirs(os.path.join(seq, "camera"))
    os.makedirs(os.path.join(seq, "applanix"))
    img = np.zeros((4, 6, 3), dtype=np.uint8)
    for stamp in kImageStampsUs:
        cv2.imwrite(os.path.join(seq, "camera", f"{stamp}.png"), img)
    with open(os.path.join(seq, "applanix", "camera_poses.csv"), "w") as f:
        f.write(kCsvHeader + "\n")
        for row in csv_rows:
            f.write(",".join(str(v) for v in row) + "\n")


def csv_row(stamp_us, xyz, roll=0.0, pitch=0.0, heading=0.0):
    return [stamp_us, *xyz, 0.0, 0.0, 0.0, roll, pitch, heading, 0.0, 0.0, 0.0]


class TestBoreasRotation(TestCase):
    def test_identity(self):
        np.testing.assert_allclose(boreas_rotation_enu_sensor(0, 0, 0), np.eye(3), atol=1e-12)

    def test_heading_90deg(self):
        # C_sensor_enu = Rz(pi/2) -> R_enu_sensor = Rz(-pi/2): sensor x axis points to -north (south)
        R = boreas_rotation_enu_sensor(0.0, 0.0, np.pi / 2)
        np.testing.assert_allclose(R[:, 0], [0, -1, 0], atol=1e-12)
        np.testing.assert_allclose(R @ R.T, np.eye(3), atol=1e-12)


class TestBoreasDataset(TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        write_sequence(self.tmp.name, [csv_row(t, [0, 0, 0]) for t in kImageStampsUs])

    def tearDown(self):
        self.tmp.cleanup()

    def make_dataset(self, start_frame_id=0):
        with contextlib.redirect_stdout(io.StringIO()):
            return BoreasDataset(
                self.tmp.name, kSequenceName, SensorType.MONOCULAR, start_frame_id, DatasetType.BOREAS
            )

    def test_timestamps_in_seconds(self):
        dataset = self.make_dataset()
        self.assertEqual(dataset.num_frames, 3)
        self.assertAlmostEqual(dataset.fps, 10.0, places=6)
        expected = [t * 1e-6 for t in kImageStampsUs]
        for i in range(3):
            img = dataset.getImageColor(i)
            self.assertIsNotNone(img)
            self.assertAlmostEqual(dataset.getTimestamp(), expected[i], places=6)
        # last frame: next timestamp is extrapolated with Ts
        self.assertAlmostEqual(dataset.getNextTimestamp(), expected[-1] + 0.1, places=6)
        self.assertIsNone(dataset.getImageColor(3))

    def test_start_frame_id(self):
        dataset = self.make_dataset(start_frame_id=1)
        dataset.getImageColor(0)
        self.assertAlmostEqual(dataset.getTimestamp(), kImageStampsUs[1] * 1e-6, places=6)
        self.assertAlmostEqual(dataset.getNextTimestamp(), kImageStampsUs[2] * 1e-6, places=6)

    def test_rejects_non_mono(self):
        with contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(ValueError):
                BoreasDataset(self.tmp.name, kSequenceName, SensorType.STEREO)


class TestBoreasPreprocessing(TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        write_sequence(self.tmp.name, [csv_row(t, [0, 0, 0]) for t in kImageStampsUs])
        # replace the images with native-size ones: top part 50, bottom 448 rows (hood) 255
        img = np.full((2048, 2448, 3), 50, dtype=np.uint8)
        img[-448:] = 255
        for stamp in kImageStampsUs:
            cv2.imwrite(os.path.join(self.tmp.name, kSequenceName, "camera", f"{stamp}.png"), img)

    def tearDown(self):
        self.tmp.cleanup()

    def make_dataset(self, **kwargs):
        with contextlib.redirect_stdout(io.StringIO()):
            return BoreasDataset(
                self.tmp.name, kSequenceName, SensorType.MONOCULAR, 0, DatasetType.BOREAS, **kwargs
            )

    def test_crop_and_scale(self):
        dataset = self.make_dataset(crop_bottom_px=448, image_scale=0.5, image_size=(1224, 800))
        img = dataset.getImageColor(0)
        self.assertEqual(img.shape, (800, 1224, 3))
        self.assertTrue(np.all(img == 50))  # hood rows are gone

    def test_no_preprocessing_by_default(self):
        img = self.make_dataset().getImageColor(0)
        self.assertEqual(img.shape, (2048, 2448, 3))

    def test_rejects_size_mismatch(self):
        with self.assertRaises(ValueError):
            self.make_dataset(crop_bottom_px=448, image_scale=0.5, image_size=(2448, 2048))


class TestBoreasGroundTruth(TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        # extra GT sample not matching any image and rows out of order: must be ignored/sorted
        rows = [
            csv_row(kImageStampsUs[2], [2.0, 0.0, 0.0], heading=np.pi / 2),
            csv_row(kImageStampsUs[0], [0.0, 0.0, 0.0]),
            csv_row(kImageStampsUs[0] + 50000, [9.0, 9.0, 9.0]),
            csv_row(kImageStampsUs[1] + 10, [1.0, 0.0, 0.0]),
        ]
        write_sequence(self.tmp.name, rows)
        with contextlib.redirect_stdout(io.StringIO()):
            self.gt = BoreasGroundTruth(self.tmp.name, kSequenceName)

    def tearDown(self):
        self.tmp.cleanup()

    def test_one_line_per_image(self):
        self.assertEqual(len(self.gt.data), 3)
        for i in range(3):
            timestamp, x, y, z, abs_scale = self.gt.getTimestampPositionAndAbsoluteScale(i)
            self.assertAlmostEqual(timestamp, kImageStampsUs[i] * 1e-6, places=6)
            self.assertAlmostEqual(x, float(i))
            self.assertAlmostEqual(abs_scale, 1.0)

    def test_orientation(self):
        _, _, _, _, qx, qy, qz, qw, _ = self.gt.getTimestampPoseAndAbsoluteScale(0)
        np.testing.assert_allclose([qx, qy, qz, qw], [0, 0, 0, 1], atol=1e-9)
        _, _, _, _, qx, qy, qz, qw, _ = self.gt.getTimestampPoseAndAbsoluteScale(2)
        np.testing.assert_allclose(
            qvec2rotmat([qx, qy, qz, qw]), boreas_rotation_enu_sensor(0, 0, np.pi / 2), atol=1e-9
        )

    def test_full_6d_trajectory(self):
        trajectory, poses, timestamps = self.gt.getFull6dTrajectory()
        self.assertEqual(len(trajectory), len(poses))
        self.assertEqual(len(trajectory), len(timestamps))
        self.assertGreater(len(timestamps), 0)


if __name__ == "__main__":
    unittest.main()
