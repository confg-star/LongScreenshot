from __future__ import annotations

from io import BytesIO

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import Response
from PIL import Image, UnidentifiedImageError

from .stitcher import StitchingError, stitch_frames

app = FastAPI(title="LongScreenshot Stitcher", version="0.1.0")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/stitch")
async def stitch(frames: list[UploadFile] = File(...)) -> Response:
    if not frames:
        raise HTTPException(status_code=422, detail="at least one frame file is required")

    images: list[Image.Image] = []
    for upload in frames:
        data = await upload.read()
        try:
            images.append(Image.open(BytesIO(data)).convert("RGB"))
        except (UnidentifiedImageError, OSError, ValueError) as error:
            raise HTTPException(status_code=400, detail=f"invalid image: {upload.filename}") from error

    try:
        result = stitch_frames(images)
    except StitchingError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error

    output = BytesIO()
    result.image.save(output, format="JPEG", quality=92, optimize=True)
    return Response(content=output.getvalue(), media_type="image/jpeg")
