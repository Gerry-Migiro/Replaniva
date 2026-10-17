"""Standalone mobile entry using the shared interactive mobile interface."""
import from .interface { MobileApp }

def:pub app -> JsxElement { return <MobileApp />; }
