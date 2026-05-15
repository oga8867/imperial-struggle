import fitz

rules_path = r'X:\Imperial Struggle\ImpStr_2nd_Printing_Rules_Final.pdf'
doc = fitz.open(rules_path)

# Page 19 bottom area has war tile fronts (we saw blue British and French side panels)
# Let's zoom into the right side of the bottom half of page 19, which seems to have the war tile fronts (blue and red)
page = doc[18]  # page 19

# Right column of page 19 bottom (has the war tile fronts)
rect = fitz.Rect(page.rect.width*0.5, page.rect.height*0.5, page.rect.width, page.rect.height)
pix = page.get_pixmap(dpi=600, clip=rect)
pix.save(r'X:\Imperial Struggle\page19_BR_zoom.png')

# Page 18 had the tan/cream colored tiles - those are advantage tile fronts
# Let's also zoom into top-left of page 18 (advantage tiles)
page18 = doc[17]
# Top-left quadrant of page 18 - the brown advantage hex tiles
rect = fitz.Rect(0, 0, page18.rect.width/2, page18.rect.height/2)
pix = page18.get_pixmap(dpi=600, clip=rect)
pix.save(r'X:\Imperial Struggle\page18_TL_advs.png')

# Top-right of page 18 - shows French wartiles?
rect = fitz.Rect(page18.rect.width*0.5, 0, page18.rect.width, page18.rect.height*0.5)
pix = page18.get_pixmap(dpi=600, clip=rect)
pix.save(r'X:\Imperial Struggle\page18_TR_zoom.png')

# Page 19 top half
rect = fitz.Rect(0, 0, page.rect.width, page.rect.height*0.5)
pix = page.get_pixmap(dpi=600, clip=rect)
pix.save(r'X:\Imperial Struggle\page19_TOP_zoom.png')

# Page 18 top half
rect = fitz.Rect(0, 0, page18.rect.width, page18.rect.height*0.5)
pix = page18.get_pixmap(dpi=600, clip=rect)
pix.save(r'X:\Imperial Struggle\page18_TOP_zoom.png')

doc.close()
print("Done")
