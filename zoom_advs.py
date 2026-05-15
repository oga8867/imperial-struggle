import fitz

rules_path = r'X:\Imperial Struggle\ImpStr_2nd_Printing_Rules_Final.pdf'
doc = fitz.open(rules_path)

# Page 18 top-right has the advantage tiles (purple)
page = doc[17]  # page 18
rect = fitz.Rect(page.rect.width*0.5, 0, page.rect.width, page.rect.height*0.55)
pix = page.get_pixmap(dpi=900, clip=rect)
pix.save(r'X:\Imperial Struggle\page18_advs.png')

# Top-left has investment tiles
rect = fitz.Rect(0, 0, page.rect.width*0.5, page.rect.height*0.55)
pix = page.get_pixmap(dpi=900, clip=rect)
pix.save(r'X:\Imperial Struggle\page18_invs.png')

# narrower zooms on advantages
rect = fitz.Rect(page.rect.width*0.5, 0, page.rect.width*0.8, page.rect.height*0.55)
pix = page.get_pixmap(dpi=1200, clip=rect)
pix.save(r'X:\Imperial Struggle\page18_advs_left.png')

rect = fitz.Rect(page.rect.width*0.7, 0, page.rect.width, page.rect.height*0.55)
pix = page.get_pixmap(dpi=1200, clip=rect)
pix.save(r'X:\Imperial Struggle\page18_advs_right.png')

doc.close()
print("Done")
