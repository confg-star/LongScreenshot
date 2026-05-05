from __future__ import annotations

import cv2
import numpy as np
from PIL import Image

from .models import StitchResult


class StitchingError(ValueError):
    pass


def stitch_frames(
    frames: list[Image.Image],
    min_overlap: int = 20,
    max_overlap: int | None = None,
) -> StitchResult:
    if not frames:
        raise StitchingError("at least one frame is required")

    rgb_frames = [frame.convert("RGB") for frame in frames]
    width = rgb_frames[0].width
    if any(frame.width != width for frame in rgb_frames):
        raise StitchingError("all frames must have the same width")

    stitched = np.array(rgb_frames[0])
    overlaps: list[int] = []

    for frame in rgb_frames[1:]:
        next_array = np.array(frame)
        overlap = _find_best_vertical_overlap(stitched, next_array, min_overlap, max_overlap)
        overlaps.append(overlap)
        stitched = np.vstack([stitched, next_array[overlap:, :, :]])

    return StitchResult(image=Image.fromarray(stitched), overlaps=overlaps)


def _find_best_vertical_overlap(
    previous: np.ndarray,
    current: np.ndarray,
    min_overlap: int,
    max_overlap: int | None,
) -> int:
    limit = min(previous.shape[0], current.shape[0]) - 1
    upper = min(max_overlap if max_overlap is not None else limit, limit)
    lower = min(min_overlap, upper)

    best_overlap = lower
    best_score = float("inf")

    previous_gray = cv2.cvtColor(previous, cv2.COLOR_RGB2GRAY)
    current_gray = cv2.cvtColor(current, cv2.COLOR_RGB2GRAY)

    for overlap in range(lower, upper + 1):
        previous_slice = previous_gray[-overlap:, :]
        current_slice = current_gray[:overlap, :]
        score = float(np.mean(cv2.absdiff(previous_slice, current_slice)))
        if score < best_score:
            best_score = score
            best_overlap = overlap

    return best_overlap
