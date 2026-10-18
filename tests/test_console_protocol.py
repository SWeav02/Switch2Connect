import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock

# Mock non-standard/Windows-native modules if running on minimal Linux environment
mock_yaml = MagicMock()
mock_yaml.load.return_value = {"profiles": {"Default": {}}}
mock_yaml.safe_load.return_value = {"profiles": {"Default": {}}}
mock_yaml.CSafeLoader = MagicMock()
mock_yaml.SafeLoader = MagicMock()

mocks = {
    "bleak": MagicMock(),
    "bleak.backends": MagicMock(),
    "bleak.backends.device": MagicMock(),
    "bleak.backends.scanner": MagicMock(),
    "bluetooth": MagicMock(),
    "win32api": MagicMock(),
    "win32con": MagicMock(),
    "winreg": MagicMock(),
    "imufusion": MagicMock(),
    "numpy": MagicMock(),
    "yaml": mock_yaml,
    "power_saving": MagicMock(),
    "keyboard_output": MagicMock(),
    "raw_input_mouse": MagicMock(),
}
for name, m in mocks.items():
    if name not in sys.modules:
        sys.modules[name] = m

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from controller import (
    ControllerInputData,
    JOYCON2_LEFT_PID,
    JOYCON2_RIGHT_PID,
    SWITCH_BUTTONS,
    CONSOLE_SESSION_START_UUID,
    CONSOLE_REPORT_RATE_UUID,
    CONSOLE_COMMAND_LEFT_UUID,
    CONSOLE_INPUT_LEFT_UUID,
    CONSOLE_EXT_RESPONSE_LEFT_UUID,
    CONSOLE_COMMAND_RIGHT_UUID,
    CONSOLE_INPUT_RIGHT_UUID,
    CONSOLE_EXT_RESPONSE_RIGHT_UUID,
)


def hex_to_bytes(s: str) -> bytes:
    return bytes.fromhex(s.replace(" ", "").replace("\n", ""))


class ConsoleProtocolPacketTests(unittest.TestCase):
    # Captured from a NYXI Hyperion 3 (right) at rest: counter 2, power 0x18, stick centred.
    resting_right = hex_to_bytes("02 18 00 00 07 00 F8 7F 00 00 00 00 00 00 00 1E")

    # Captured flat, button face up, so gravity sits on z at 4096 = 1 g.
    flat_right = hex_to_bytes(
        "46 18 00 00 07 00 B8 7F 00 00 00 00 00 00 00 1E FF 86 01 0C 02 00 33 56 01 2F 0F 2C 00 "
        "3A AB 89 00 00 02 01 00 00 84 FF 00 00 F6 0F 00 00 00 00 00 00 00 00 00 00 00 00 00 "
        "00 00 00 00 00 00"
    )
    flat_left = hex_to_bytes(
        "46 18 00 00 07 F1 17 82 00 00 00 00 00 00 1E FC 8E 01 0C 00 2E 88 BA 01 8E 52 08 01 A3 "
        "ED 77 00 00 99 FF 00 00 1C 00 00 00 EF 0F 00 00 00 00 00 00 00 00 00 00 00 00 00 00 "
        "00 00 00 00 00 00"
    )

    def _make_report(self, base_bytes: bytes, buttons: int, power: int = 0x18) -> bytes:
        data = bytearray(base_bytes.ljust(63, b"\x00"))
        data[1] = power & 0xFF
        data[2] = buttons & 0xFF
        data[3] = (buttons >> 8) & 0xFF
        return bytes(data)

    def test_decodes_packed_stick(self):
        input_data = ControllerInputData(
            self.resting_right.ljust(63, b"\x00"),
            None,
            None,
            product_id=JOYCON2_RIGHT_PID,
            is_console_protocol=True,
        )
        self.assertEqual(input_data.right_stick[0], 2048)
        self.assertEqual(input_data.right_stick[1], 2047)

    def test_right_face_and_system_buttons(self):
        # 0b0101_0001_0000_0011: B (bit 0), A (bit 1), Home (bit 8), C (bit 12), SR (bit 14)
        raw_buttons = 0b0101_0001_0000_0011
        report = self._make_report(self.resting_right, raw_buttons)
        input_data = ControllerInputData(
            report,
            None,
            None,
            product_id=JOYCON2_RIGHT_PID,
            is_console_protocol=True,
        )
        expected = (
            SWITCH_BUTTONS["B"]
            | SWITCH_BUTTONS["A"]
            | SWITCH_BUTTONS["HOME"]
            | SWITCH_BUTTONS["C"]
            | SWITCH_BUTTONS["SR_R"]
        )
        self.assertEqual(input_data.buttons, expected)

    def test_left_buttons(self):
        # 0b1000_0001_1111_0001: Down(0), L(4), ZL(5), -(6), LS(7), Capture(8), SL(15)
        raw_buttons = 0b1000_0001_1111_0001
        report = self._make_report(self.resting_right, raw_buttons)
        input_data = ControllerInputData(
            report,
            None,
            None,
            product_id=JOYCON2_LEFT_PID,
            is_console_protocol=True,
        )
        expected = (
            SWITCH_BUTTONS["DOWN"]
            | SWITCH_BUTTONS["L"]
            | SWITCH_BUTTONS["ZL"]
            | SWITCH_BUTTONS["MINUS"]
            | SWITCH_BUTTONS["L_STK"]
            | SWITCH_BUTTONS["CAPT"]
            | SWITCH_BUTTONS["SL_L"]
        )
        self.assertEqual(input_data.buttons, expected)

    def test_battery_level(self):
        # Power level 9 -> 9 << 2 = 0x24
        rep_full = self._make_report(self.resting_right, 0, power=(9 << 2))
        input_full = ControllerInputData(
            rep_full, None, None, product_id=JOYCON2_RIGHT_PID, is_console_protocol=True
        )
        self.assertAlmostEqual(input_full.battery_voltage, 4.0, places=1)

        # Power level 5 -> 5 << 2 = 0x14
        rep_mid = self._make_report(self.resting_right, 0, power=(5 << 2))
        input_mid = ControllerInputData(
            rep_mid, None, None, product_id=JOYCON2_RIGHT_PID, is_console_protocol=True
        )
        self.assertAlmostEqual(input_mid.battery_voltage, 3.64, places=1)

    def test_right_accelerometer_orientation(self):
        input_data = ControllerInputData(
            self.flat_right,
            None,
            None,
            product_id=JOYCON2_RIGHT_PID,
            is_console_protocol=True,
        )
        ax, ay, az = input_data.accelerometer
        self.assertEqual(ax, 258)
        self.assertEqual(ay, 124)  # raw is -124, negated is 124
        self.assertEqual(az, 4086)

    def test_left_accelerometer_orientation(self):
        input_data = ControllerInputData(
            self.flat_left,
            None,
            None,
            product_id=JOYCON2_LEFT_PID,
            is_console_protocol=True,
        )
        ax, ay, az = input_data.accelerometer
        self.assertEqual(ax, -103)
        self.assertEqual(ay, -28)  # raw is 28, negated is -28
        self.assertEqual(az, 4079)

    def test_console_uuids_defined(self):
        self.assertEqual(CONSOLE_SESSION_START_UUID, "00c5af5d-1964-4e30-8f51-1956f96bd282")
        self.assertEqual(CONSOLE_REPORT_RATE_UUID, "679d5510-5a24-4dee-9557-95df80486ecb")
        self.assertEqual(CONSOLE_COMMAND_LEFT_UUID, "ce49a830-dced-48ae-931e-c8cf88aadbea")
        self.assertEqual(CONSOLE_INPUT_LEFT_UUID, "cc1bbbb5-7354-4d32-a716-a81cb241a32a")
        self.assertEqual(CONSOLE_EXT_RESPONSE_LEFT_UUID, "63a3810f-aec7-474b-9010-3d52403cb996")
        self.assertEqual(CONSOLE_COMMAND_RIGHT_UUID, "65a724b3-f1e7-4a61-8078-a342376b27ff")
        self.assertEqual(CONSOLE_INPUT_RIGHT_UUID, "d5a9e01e-2ffc-4cca-b20c-8b67142bf442")
        self.assertEqual(CONSOLE_EXT_RESPONSE_RIGHT_UUID, "640ca58e-0e88-410c-a7f3-426faf2b690b")


if __name__ == "__main__":
    unittest.main()
