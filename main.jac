"""Replaniva private personal planning application."""
import ".planner.css";
import from .frontend { app as ClientApp }
def:pub app -> JsxElement {
    <ClientApp/>
}
