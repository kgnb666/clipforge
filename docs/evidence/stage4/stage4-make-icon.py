"""ClipForge 应用图标生成（1024x1024 PNG，供 `npx tauri icon` 生成全套平台图标）。

设计说明（"特色"取舍）：
- 圆角方块 + 靛蓝→青 对角渐变：桌面客户端底色，冷暖之间可读性稳定（浅色/深色任务栏）。
- 白色胶片画框（round rect 描边）+ 顶/底齿孔缺口：直接表达"视频/剪辑"。
- 金色→橙 渐变播放三角 + 柔和投影："转换/播放"的通用符号，同时呼应 Forge 的暖色。

输出：docs/evidence/stage4/clipforge-icon-1024.png（透明四角）
依赖：Pillow（仅生成期使用，不进入产品依赖）
"""
from PIL import Image, ImageDraw, ImageFilter

S = 1024
OUT = r"D:\Cliporge\docs\evidence\stage4\clipforge-icon-1024.png"

# ---------- 1. 背景：对角渐变 + 圆角遮罩 ----------
STOPS = [
    (0.00, (67, 56, 202)),    # indigo-700  #4338CA
    (0.55, (37, 99, 235)),    # blue-600    #2563EB
    (1.00, (14, 116, 144)),   # cyan-700    #0E7490
]


def grad_color(t):
    for i in range(len(STOPS) - 1):
        t0, c0 = STOPS[i]
        t1, c1 = STOPS[i + 1]
        if t0 <= t <= t1:
            k = (t - t0) / (t1 - t0)
            return tuple(round(c0[j] + (c1[j] - c0[j]) * k) for j in range(3))
    return STOPS[-1][1]


small = 64
grad = Image.new("RGB", (small, small))
px = grad.load()
for y in range(small):
    for x in range(small):
        px[x, y] = grad_color((x + y) / (2 * (small - 1)))
grad = grad.resize((S, S), Image.BICUBIC)

mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=224, fill=255)

base = Image.new("RGBA", (S, S), (0, 0, 0, 0))
base.paste(grad, (0, 0), mask=mask)

# ---------- 2. 金色播放三角（含投影） ----------
CX, CY = 512 + 16, 512
HW, HH, R = 118, 126, 30
pts = [(CX - HW, CY - HH), (CX - HW, CY + HH), (CX + HW, CY)]

tri_mask = Image.new("L", (S, S), 0)
td = ImageDraw.Draw(tri_mask)
td.polygon(pts, fill=255)
for vx, vy in pts:
    td.ellipse([vx - R, vy - R, vx + R, vy + R], fill=255)

gold = Image.new("RGB", (small, small))
gpx = gold.load()
G0, G1 = (251, 191, 36), (249, 115, 22)   # amber-400 -> orange-500
for y in range(small):
    for x in range(small):
        t = (x + y) / (2 * (small - 1))
        gpx[x, y] = tuple(round(G0[j] + (G1[j] - G0[j]) * t) for j in range(3))
gold = gold.resize((S, S), Image.BICUBIC)

triangle = Image.new("RGBA", (S, S), (0, 0, 0, 0))
triangle.paste(gold, (0, 0), mask=tri_mask)

shadow_alpha = tri_mask.filter(ImageFilter.GaussianBlur(22)).point(lambda a: int(a * 0.42))
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
shadow.putalpha(shadow_alpha)

# ---------- 3. 白色胶片画框 + 齿孔缺口 ----------
frame = Image.new("RGBA", (S, S), (0, 0, 0, 0))
fd = ImageDraw.Draw(frame)
FX0, FY0, FX1, FY1 = 512 - 336, 512 - 248, 512 + 336, 512 + 248
fd.rounded_rectangle([FX0, FY0, FX1, FY1], radius=76, outline=(255, 255, 255, 255), width=64)

# 齿孔：在顶/底边框上打穿（RGBA 直写透明），露出渐变底 => 胶片条孔洞
for cx in (512 - 195, 512 - 65, 512 + 65, 512 + 195):
    for cy in (FY0, FY1):
        fd.rounded_rectangle([cx - 39, cy - 18, cx + 39, cy + 18], radius=10, fill=(0, 0, 0, 0))

# ---------- 4. 合成 ----------
out = base.copy()
out.alpha_composite(shadow, (0, 18))
out.alpha_composite(frame)
out.alpha_composite(triangle)
out.save(OUT)
print(f"OK {OUT} {out.size}")
