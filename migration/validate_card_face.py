from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    main_lua = (ROOT / "scripts/main.lua").read_text(encoding="utf-8")
    renderer_lua = (ROOT / "scripts/migration/Renderer.lua").read_text(encoding="utf-8")
    errors: list[str] = []

    def expect(condition: bool, message: str) -> None:
        if not condition:
            errors.append(message)

    expect("painter_:DrawCardSymbol(id, 0, 7, titleColor)" in main_lua,
           "card art does not use the deterministic vector renderer")
    expect("nvgScale(painter_.vg, CARD_TEXT_SCALE, CARD_TEXT_SCALE)" in main_lua,
           "card art does not use the Phaser card-container scale")
    expect("def.symbol" not in main_lua,
           "card face can fall back to unavailable browser glyphs")
    expect("ruleFlash_.cardId" in main_lua
           and "painter_:DrawCardSymbol(ruleFlash_.cardId, 0, 0" in main_lua,
           "rule feedback can fall back to unavailable browser glyphs")
    expect("painter_:DrawCardSymbol(event.cardId, 0, 0" in main_lua
           and "painter_:DrawCardSymbol(item.cardId, 0, 0" in main_lua,
           "replay icon paths can fall back to unavailable browser glyphs")
    expect("item.symbol" not in main_lua,
           "replay rule feed still draws unavailable browser glyphs")
    expect("nvgTextLineHeight(self.vg, lineHeight or 1)" in renderer_lua,
           "renderer cannot set source-equivalent card text line height")
    expect('"maker-body", 1.2)' in main_lua,
           "card description does not preserve Phaser 10px + 2px line spacing")
    expect("function Renderer:DrawNavigationIcon(kind" in renderer_lua and 'kind == "reset"' in renderer_lua,
           "reset control does not use the deterministic vector renderer")
    for card_id in ("feather-gravity", "side-gravity", "hooke-bounce", "up-impulse", "mirror-motion", "quantum-phase"):
        expect(f'id == "{card_id}"' in renderer_lua, f"missing vector artwork for {card_id}")

    if errors:
        print("CARD_FACE_VALIDATE fail")
        for error in errors:
            print(f"- {error}")
        return 1
    print("CARD_FACE_VALIDATE pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
