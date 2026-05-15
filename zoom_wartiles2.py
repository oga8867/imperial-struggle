import fitz

rules_path = r'X:\Imperial Struggle\ImpStr_2nd_Printing_Rules_Final.pdf'
doc = fitz.open(rules_path)

# Page 19 has the British Bonus War Tiles (top-left of page 19)
page = doc[18]  # page 19

# Top-left quadrant should be just the British war tiles area
rect = fitz.Rect(0, 0, page.rect.width*0.5, page.rect.height*0.5)
pix = page.get_pixmap(dpi=600, clip=rect)
pix.save(r'X:\Imperial Struggle\page19_TL_zoom.png')

# Need higher detail - half of half
rect = fitz.Rect(0, 0, page.rect.width*0.3, page.rect.height*0.5)
pix = page.get_pixmap(dpi=800, clip=rect)
pix.save(r'X:\Imperial Struggle\page19_TL_left_zoom.png')

rect = fitz.Rect(page.rect.width*0.2, 0, page.rect.width*0.5, page.rect.height*0.5)
pix = page.get_pixmap(dpi=800, clip=rect)
pix.save(r'X:\Imperial Struggle\page19_TL_right_zoom.png')

# Let's also do a vertical strip - the right side (yellow/black markers and red)
rect = fitz.Rect(page.rect.width*0.4, 0, page.rect.width*0.55, page.rect.height*0.55)
pix = page.get_pixmap(dpi=800, clip=rect)
pix.save(r'X:\Imperial Struggle\page19_basic_strip.png')

doc.close()
print("Done")
