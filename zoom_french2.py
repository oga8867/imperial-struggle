import fitz

rules_path = r'X:\Imperial Struggle\ImpStr_2nd_Printing_Rules_Final.pdf'
doc = fitz.open(rules_path)

# Page 18 bottom-left = French Sheet #4 FRONT
page = doc[17]
rect = fitz.Rect(0, page.rect.height*0.5, page.rect.width*0.5, page.rect.height)
pix = page.get_pixmap(dpi=700, clip=rect)
pix.save(r'X:\Imperial Struggle\page18_FR_wartiles.png')

# narrower zoom
rect = fitz.Rect(0, page.rect.height*0.5, page.rect.width*0.3, page.rect.height)
pix = page.get_pixmap(dpi=900, clip=rect)
pix.save(r'X:\Imperial Struggle\page18_FR_wartiles_left.png')

rect = fitz.Rect(page.rect.width*0.2, page.rect.height*0.5, page.rect.width*0.5, page.rect.height)
pix = page.get_pixmap(dpi=900, clip=rect)
pix.save(r'X:\Imperial Struggle\page18_FR_wartiles_right.png')

doc.close()
print("Done")
