"""Hosted provider adapters. Importing this package registers each one in providers.REGISTRY."""
from . import (  # noqa: F401
    fal_image, fal_trellis, google_image, meshy_3d, openai_image, rodin_3d, tripo_3d,
)
