from dataclasses import dataclass

from PIL import Image


@dataclass(frozen=True)
class StitchResult:
    image: Image.Image
    overlaps: list[int]
