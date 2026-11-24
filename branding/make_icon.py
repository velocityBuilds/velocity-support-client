# Generates the placeholder VelocitySupport icon. Replace branding/icon-source.png
# with your real logo (square, 1024px) and re-run to regenerate every icon file.
import sys, os
from PIL import Image, ImageDraw, ImageFont
root = sys.argv[1]
src = os.path.join(os.path.dirname(__file__), "icon-source.png")
S = 1024
if os.path.exists(src):
    img = Image.open(src).convert("RGBA").resize((S, S), Image.LANCZOS)
else:
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # rounded square with a subtle top-to-bottom gradient
    grad = Image.new("RGBA", (S, S))
    gd = ImageDraw.Draw(grad)
    for y in range(S):
        t = y / S
        c = (int(59 + (29 - 59) * t), int(130 + (78 - 130) * t), int(246 + (216 - 246) * t), 255)
        gd.line([(0, y), (S, y)], fill=c)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=230, fill=255)
    img.paste(grad, (0, 0), mask)
    # speed lines
    for i, (y, w) in enumerate([(380, 170), (500, 230), (620, 170)]):
        d.rounded_rectangle([150, y, 150 + w, y + 38], radius=19, fill=(255, 255, 255, 150))
    # bold V
    font = ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", 720)
    bbox = d.textbbox((0, 0), "V", font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text(((S - tw) / 2 + 70 - bbox[0], (S - th) / 2 - bbox[1] + 10), "V", font=font, fill="white")
sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
img.save(os.path.join(root, "res/icon.ico"), sizes=sizes)
img.save(os.path.join(root, "res/tray-icon.ico"), sizes=sizes)
img.save(os.path.join(root, "flutter/windows/runner/resources/app_icon.ico"), sizes=sizes)
img.resize((512, 512), Image.LANCZOS).save(os.path.join(root, "res/icon.png"))
img.resize((512, 512), Image.LANCZOS).save(os.path.join(root, "flutter/assets/icon.png"))
for n in (32, 64, 128):
    img.resize((n, n), Image.LANCZOS).save(os.path.join(root, f"res/{n}x{n}.png"))
img.resize((512, 512), Image.LANCZOS).save(os.path.join(os.path.dirname(__file__), "icon-preview.png"))
print("icons written")
