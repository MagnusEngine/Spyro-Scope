using System;
namespace SpyroScope {
	class Button : GUIElement {
		public Renderer.Color normal = .(255, 255, 255);
		public Renderer.Color hovered = .(255, 255, 128);
		public Renderer.Color pressed = .(255, 255, 255);
		public Renderer.Color disabled = .(128, 128, 128);

		public Texture normalTexture = Renderer.whiteTexture;
		public Texture pressedTexture = Renderer.whiteTexture;

		public Texture iconTexture;

		public bool enabled = true;
		public Event<delegate void()> OnPressed ~ _.Dispose();

		public override void Draw(Rect parentRect, Renderer renderer) {
			base.Draw(parentRect, renderer);

			Renderer.Color color = disabled;
			Texture texture = pressedTexture;
			if (enabled) {
				color = normal;
				texture = normalTexture;
				if (GUIElement.hoveredElement == this || GUIElement.preselectedElement == this) {
					color = hovered;
					if (GUIElement.hoveredElement == GUIElement.preselectedElement) {
						color = pressed;
						texture = pressedTexture;
					}
				}
			}
			DrawUtilities.SlicedRect(drawn.bottom, drawn.top, drawn.left, drawn.right, 1,0,0,1, 0.7f,0.3f,0.3f,0.7f, texture, color, renderer);

			if (iconTexture != null) {
				let hcenter = (drawn.left + drawn.right) / 2;
				let vcenter = (drawn.top + drawn.bottom) / 2;
				let halfWidth = iconTexture.width / 2;
				let halfHeight = iconTexture.height / 2;
				DrawUtilities.Rect(vcenter - halfHeight, vcenter + halfHeight, hcenter - halfHeight, hcenter + halfHeight, 1,0,0,1, iconTexture, color, renderer);
			}
		}

		public override void Pressed() {
			if (enabled) {
				OnPressed();
			}
		}
	}
}