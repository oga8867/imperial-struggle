import fitz

rules_path = r'X:\Imperial Struggle\ImpStr_2nd_Printing_Rules_Final.pdf'
doc = fitz.open(rules_path)

# British basic war tiles - rightmost column of British sheet (page 19, top-left).
# Looking at the image, the basic tiles are at approx x=0.32-0.42 of the page width, top half
page = doc[18]  # page 19
# Just the basic tile column
rect = fitz.Rect(page.rect.width*0.30, 0, page.rect.width*0.45, page.rect.height*0.5)
pix = page.get_pixmap(dpi=1200, clip=rect)
pix.save(r'X:\Imperial Struggle\page19_BR_basic.png')

# French basic war tiles - rightmost column of French sheet (page 18, bottom-left).
page = doc[17]  # page 18
rect = fitz.Rect(page.rect.width*0.30, page.rect.height*0.5, page.rect.width*0.45, page.rect.height)
pix = page.get_pixmap(dpi=1200, clip=rect)
pix.save(r'X:\Imperial Struggle\page18_FR_basic.png')

doc.close()
print("Done")
