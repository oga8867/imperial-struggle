import fitz

rules_path = r'X:\Imperial Struggle\ImpStr_2nd_Printing_Rules_Final.pdf'
doc = fitz.open(rules_path)
# Pages 17, 18, 19 (0-indexed = 17, 18 are likely manifest)
for i in [16, 17, 18, 19]:
    if i < len(doc):
        print(f"\n=== PAGE {i+1} TEXT ===")
        print(doc[i].get_text())
        # Save page as image too
        pix = doc[i].get_pixmap(dpi=200)
        pix.save(rf'X:\Imperial Struggle\rules_page_{i+1}.png')
doc.close()
print("\n\nSaved page images to rules_page_*.png")
