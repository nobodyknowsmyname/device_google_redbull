#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Clean downstream UAPI additions without shadowing Bionic's kernel headers."""

import os
from pathlib import Path
import re
import sys


def clean_headers(root, source, destination, headers):
    os.environ["ANDROID_BUILD_TOP"] = str(root)
    sys.path.insert(0, str(root / "bionic/libc/kernel/tools"))
    import clean_header

    for relative in headers:
        original = source / relative
        # Downstream UAPI contains userspace buffer-layout helpers. Bionic's
        # cleaner removes functions unless they are explicitly preserved.
        inline_functions = re.findall(
            r"\bstatic\s+(?:__inline__|inline|__always_inline)\s+"
            r"[\w\s*]+?\b(\w+)\s*\(", original.read_text(encoding="latin-1"))
        clean_header.kernel_known_generic_statics.update(inline_functions)
        target = destination / relative
        cleaned = clean_header.cleanupFile(str(target), str(original), relative)
        if cleaned is None:
            raise RuntimeError(f"Failed to clean kernel header: {relative}")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(cleaned)


def fix_platform_includes(destination, platform_headers):
    for header in destination.rglob("*.h"):
        def replace(match):
            relative = Path(os.path.normpath(
                str(header.relative_to(destination).parent / match.group(1))))
            if any((base / relative).exists() for base in platform_headers):
                return f"#include <{relative.as_posix()}>"
            return match.group(0)
        text = header.read_text()
        cleaned = re.sub(r'#\s*include\s*"([^"]+)"', replace, text)
        if cleaned != text:
            header.write_text(cleaned)


def add_downstream_macros(root, source, destination):
    extensions = {
        "drm/drm_fourcc.h": "DRM_FORMAT_MOD_QCOM_",
        "drm/drm_mode.h": "DRM_MODE_",
        "linux/videodev2.h": "V4L2_PIX_FMT_",
    }
    for path, prefix in extensions.items():
        relative = Path(path)
        platform = (root / "bionic/libc/kernel/uapi" / relative).read_text()
        original = (source / relative).read_text(encoding="latin-1")
        original = original.replace("\\\n", " ")
        definitions = re.findall(
            rf"^#\s*define\s+({prefix}\w+)\s+(.+)$", original, re.MULTILINE)
        text = "/* Generated downstream Qualcomm UAPI additions. */\n"
        text += f"#pragma once\n#include_next <{path}>\n"
        for name, value in definitions:
            if not re.search(rf"^#\s*define\s+{name}\b", platform, re.MULTILINE):
                text += f"#ifndef {name}\n#define {name} {value.strip()}\n#endif\n"
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)


def main():
    root = Path(__file__).resolve().parents[3]
    source, destination = map(lambda p: Path(p).resolve(), sys.argv[1:])
    platform_headers = [
        root / "bionic/libc/kernel/uapi",
        root / "bionic/libc/kernel/android/uapi",
        root / "bionic/libc/kernel/android/scsi",
    ]
    # Qualcomm's downstream DRM ioctls are absent from the upstream header.
    device_overrides = {"drm/msm_drm.h"}
    headers = []
    for header in sorted(source.rglob("*.h")):
        relative = header.relative_to(source)
        if relative.parts[0] in {"asm", "asm-generic"}:
            continue
        if str(relative) not in device_overrides and any(
            (base / relative).exists() for base in platform_headers):
            continue
        headers.append(str(relative))

    destination.mkdir(parents=True, exist_ok=True)
    clean_headers(root, source, destination, headers)
    for header in headers:
        if not (destination / header).is_file():
            raise RuntimeError(f"Failed to clean kernel header: {header}")
    fix_platform_includes(destination, platform_headers)
    add_downstream_macros(root, source, destination)
    print(f"Prepared {len(list(destination.rglob('*.h')))} downstream headers "
          "for Android userspace.")


if __name__ == "__main__":
    main()
