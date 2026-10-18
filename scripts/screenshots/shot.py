import re, sys, html, pathlib
from playwright.sync_api import sync_playwright
d = pathlib.Path(sys.argv[1])
views = [("board", "~/journal — :Logpose board"), ("today", ":Logpose today"), ("projects", ":Logpose projects")]
out = pathlib.Path(sys.argv[2]); out.mkdir(exist_ok=True)
with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(device_scale_factor=2, viewport={"width": 1600, "height": 900})
    for name, title in views:
        src = (d / f"{name}.html").read_text()
        style = re.search(r"<style>(.*?)</style>", src, re.S).group(1)
        style = re.sub(r"^\*.*$", "", style, flags=re.M).replace("body {", ".term {")
        pre = re.search(r"<pre>(.*?)</pre>", src, re.S).group(1).rstrip()
        winbar = (d / f"{name}.txt").read_text().split("\n", 1)[0].rstrip()
        wb = ""
        if winbar.strip():
            left, _, right = winbar.strip().partition("  ")
            wb = f'<div class="winbar"><b>{html.escape(left.split(" · ")[0])}</b> · {html.escape(" · ".join(left.split(" · ")[1:]))}<span>{html.escape(right.strip())}</span></div>'
        page = f"""<!doctype html><meta charset=utf-8><style>
        body {{ margin:0; background:transparent; }}
        .win {{ display:inline-block; margin:24px; border-radius:10px; overflow:hidden;
               box-shadow: 0 12px 32px rgba(0,0,0,.35), 0 0 0 1px rgba(255,255,255,.06); }}
        .bar {{ background:#15161e; color:#565f89; font:12px -apple-system, 'DejaVu Sans', sans-serif;
               padding:9px 14px; position:relative; text-align:center; }}
        .bar i {{ position:absolute; left:14px; top:11px; }}
        .bar i b {{ display:inline-block; width:11px; height:11px; border-radius:50%; margin-right:7px; background:#2f3346; }}
        .term {{ padding:10px 18px 16px; }}
        .term, .term * {{ font-family:'DejaVu Sans Mono', monospace; font-size:13.5px; line-height:1.32; }}
        pre {{ margin:0; }}
        .winbar {{ font-family:'DejaVu Sans Mono',monospace; font-size:13.5px; color:#a9b1d6; background:#16161e;
                  margin:-10px -18px 10px; padding:5px 18px; display:flex; gap:.5ch; }}
        .winbar span {{ margin-left:auto; color:#565f89; }}
        {style}
        </style><div class=win><div class=bar><i><b></b><b></b><b></b></i>{html.escape(title)}</div>
        <div class=term>{wb}<pre>{pre}</pre></div></div>"""
        pg.set_content(page)
        pg.locator(".win").screenshot(path=str(out / f"{name}.png"), omit_background=True)
        print("wrote", name)
    b.close()
