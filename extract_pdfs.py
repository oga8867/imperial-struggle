import fitz
import os

rules_path = r'X:\Imperial Struggle\ImpStr_2nd_Printing_Rules_Final.pdf'
playbook_path = r'X:\Imperial Struggle\vassal_extracted\ImpStr_Living_Playbook_7-26-20.pdf'

print("="*80)
print("RULES PDF")
print("="*80)
doc = fitz.open(rules_path)
print(f"Pages: {len(doc)}")
for i in range(len(doc)):
    print(f"\n--- RULES PAGE {i+1} ---")
    print(doc[i].get_text())
doc.close()
