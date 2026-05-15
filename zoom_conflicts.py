import fitz

rules_path = r'X:\Imperial Struggle\ImpStr_2nd_Printing_Rules_Final.pdf'
doc = fitz.open(rules_path)

# Conflict markers were visible in lower right of the British wartile sheet (page 19)
page = doc[18]  # page 19
# Far right column of page 19 top half - that has Conflict + Atlantic Turnaround
rect = fitz.Rect(page.rect.width*0.38, 0, page.rect.width*0.55, page.rect.height*0.55)
pix = page.get_pixmap(dpi=1200, clip=rect)
pix.save(r'X:\Imperial Struggle\page19_conflicts.png')

# Look at French side too
page = doc[17]
rect = fitz.Rect(page.rect.width*0.38, page.rect.height*0.5, page.rect.width*0.55, page.rect.height)
pix = page.get_pixmap(dpi=1200, clip=rect)
pix.save(r'X:\Imperial Struggle\page18_FR_conflicts.png')

doc.close()
print("Done")
