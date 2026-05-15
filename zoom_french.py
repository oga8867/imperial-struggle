import fitz

rules_path = r'X:\Imperial Struggle\ImpStr_2nd_Printing_Rules_Final.pdf'
doc = fitz.open(rules_path)

# Page 19 right (top) - might be French or back - we saw it was reddish/dark
# Actually the British tiles are top-left of page 19. Top-right of page 19 has dark red/maroon = French wartiles?
page = doc[18]  # page 19
rect = fitz.Rect(page.rect.width*0.5, 0, page.rect.width, page.rect.height*0.5)
pix = page.get_pixmap(dpi=600, clip=rect)
pix.save(r'X:\Imperial Struggle\page19_TR_zoom2.png')

doc.close()
print("Done")
