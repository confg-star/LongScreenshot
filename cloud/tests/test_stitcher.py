from PIL import Image, ImageDraw

from longshot_stitcher.stitcher import StitchingError, stitch_frames


def make_document(width: int = 80, height: int = 220) -> Image.Image:
    image = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(image)
    for y in range(height):
        color = (y % 251, (y * 3) % 251, (y * 7) % 251)
        draw.line([(0, y), (width, y)], fill=color)
    for y in range(0, height, 20):
        draw.rectangle((6, y + 4, width - 6, min(y + 12, height - 1)), fill="black")
    return image


def test_stitch_frames_reconstructs_vertical_scroll():
    document = make_document()
    frames = [
        document.crop((0, 0, 80, 100)),
        document.crop((0, 60, 80, 160)),
        document.crop((0, 120, 80, 220)),
    ]

    result = stitch_frames(frames, min_overlap=20, max_overlap=90)

    assert result.image.size == (80, 220)
    assert result.overlaps == [40, 40]


def test_stitch_frames_rejects_empty_input():
    try:
        stitch_frames([])
    except StitchingError as error:
        assert str(error) == "at least one frame is required"
    else:
        raise AssertionError("expected StitchingError")


def test_stitch_frames_rejects_mismatched_widths():
    first = Image.new("RGB", (80, 100), "white")
    second = Image.new("RGB", (81, 100), "white")

    try:
        stitch_frames([first, second])
    except StitchingError as error:
        assert str(error) == "all frames must have the same width"
    else:
        raise AssertionError("expected StitchingError")
