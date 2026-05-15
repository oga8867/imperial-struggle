import fitz
rules_path = r'X:\Imperial Struggle\ImpStr_2nd_Printing_Rules_Final.pdf'
doc = fitz.open(rules_path)
# Page 19's bottom-right area has the British wartiles + conflict markers in narrow far right
page = doc[18]  # page 19
# Right edge column - from bottom-right position
rect = fitz.Rect(page.rect.width*0.43, 0, page.rect.width*0.5, page.rect.height*0.55)
pix = page.get_pixmap(dpi=1500, clip=rect)
pix.save(r'X:\Imperial Struggle\page19_only_conflict.png')

# Page 18's french side conflict
page = doc[17]
rect = fitz.Rect(page.rect.width*0.43, page.rect.height*0.5, page.rect.width*0.5, page.rect.height)
pix = page.get_pixmap(dpi=1500, clip=rect)
pix.save(r'X:\Imperial Struggle\page18_only_conflict.png')

doc.close()
print("Done")
