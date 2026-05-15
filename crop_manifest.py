import fitz

rules_path = r'X:\Imperial Struggle\ImpStr_2nd_Printing_Rules_Final.pdf'
doc = fitz.open(rules_path)

# Render page 19 (index 18) at very high DPI to read individual tiles
page = doc[18]  # page 19 is the British/French war tiles sheet
pix = page.get_pixmap(dpi=400)
pix.save(r'X:\Imperial Struggle\rules_page_19_hires.png')

# British war tiles bottom-left of page 19
# Let's crop sections
import os
# Page is approx 612x792 points * (400/72) = pixels. Let's get the dimensions
print(f"Page 19 size: {pix.width} x {pix.height}")

# Crop bottom-left quadrant (British war tiles)
rect = fitz.Rect(0, page.rect.height/2, page.rect.width/2, page.rect.height)
pix2 = page.get_pixmap(dpi=400, clip=rect)
pix2.save(r'X:\Imperial Struggle\rules_page_19_BR_wartiles.png')

# Also page 18 bottom-left for British
page18 = doc[17]
rect = fitz.Rect(0, page18.rect.height/2, page18.rect.width/2, page18.rect.height)
pix3 = page18.get_pixmap(dpi=400, clip=rect)
pix3.save(r'X:\Imperial Struggle\rules_page_18_BL.png')

# Page 18 bottom-right (French war tiles?)
rect = fitz.Rect(page18.rect.width/2, page18.rect.height/2, page18.rect.width, page18.rect.height)
pix4 = page18.get_pixmap(dpi=400, clip=rect)
pix4.save(r'X:\Imperial Struggle\rules_page_18_BR.png')

# Page 19 bottom-right (French war tiles)
rect = fitz.Rect(page.rect.width/2, page.rect.height/2, page.rect.width, page.rect.height)
pix5 = page.get_pixmap(dpi=400, clip=rect)
pix5.save(r'X:\Imperial Struggle\rules_page_19_BR.png')

# Page 18 top sections (Bonus war tile sheets)
rect = fitz.Rect(0, 0, page18.rect.width/2, page18.rect.height/2)
pix6 = page18.get_pixmap(dpi=400, clip=rect)
pix6.save(r'X:\Imperial Struggle\rules_page_18_TL.png')

rect = fitz.Rect(page18.rect.width/2, 0, page18.rect.width, page18.rect.height/2)
pix7 = page18.get_pixmap(dpi=400, clip=rect)
pix7.save(r'X:\Imperial Struggle\rules_page_18_TR.png')

rect = fitz.Rect(0, 0, page.rect.width/2, page.rect.height/2)
pix8 = page.get_pixmap(dpi=400, clip=rect)
pix8.save(r'X:\Imperial Struggle\rules_page_19_TL.png')

rect = fitz.Rect(page.rect.width/2, 0, page.rect.width, page.rect.height/2)
pix9 = page.get_pixmap(dpi=400, clip=rect)
pix9.save(r'X:\Imperial Struggle\rules_page_19_TR.png')

print("Cropped images saved.")
doc.close()
