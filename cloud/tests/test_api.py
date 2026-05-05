from io import BytesIO

from fastapi.testclient import TestClient
from PIL import Image, ImageDraw

from longshot_stitcher.api import app


client = TestClient(app)
client_without_server_exceptions = TestClient(app, raise_server_exceptions=False)


def make_document(width: int = 80, height: int = 160) -> Image.Image:
    image = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(image)
    for y in range(height):
        draw.line([(0, y), (width, y)], fill=(y % 255, (y * 5) % 255, (y * 9) % 255))
    return image


def as_upload(name: str, image: Image.Image) -> tuple[str, tuple[str, bytes, str]]:
    buffer = BytesIO()
    image.save(buffer, format="JPEG", quality=92)
    return "frames", (name, buffer.getvalue(), "image/jpeg")


def test_health_endpoint():
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_stitch_endpoint_returns_jpeg():
    document = make_document()
    frames = [
        document.crop((0, 0, 80, 100)),
        document.crop((0, 60, 80, 160)),
    ]
    files = [as_upload(f"frame-{index}.jpg", frame) for index, frame in enumerate(frames)]

    response = client.post("/stitch", files=files)

    assert response.status_code == 200
    assert response.headers["content-type"] == "image/jpeg"
    returned = Image.open(BytesIO(response.content))
    assert returned.size == (80, 160)


def test_stitch_endpoint_rejects_missing_frames():
    response = client.post("/stitch", files=[])

    assert response.status_code == 422


def test_stitch_endpoint_rejects_invalid_image_upload():
    buffer = BytesIO()
    make_document().save(buffer, format="JPEG", quality=92)
    corrupt_jpeg = buffer.getvalue()[:-10]

    response = client_without_server_exceptions.post(
        "/stitch",
        files=[("frames", ("broken.jpg", corrupt_jpeg, "image/jpeg"))],
    )

    assert response.status_code == 400
    assert response.json() == {"detail": "invalid image: broken.jpg"}


def test_stitch_endpoint_converts_stitching_error_to_http_400():
    files = [
        as_upload("frame-0.jpg", make_document(width=80)),
        as_upload("frame-1.jpg", make_document(width=64)),
    ]

    response = client.post("/stitch", files=files)

    assert response.status_code == 400
    assert response.json() == {"detail": "all frames must have the same width"}
