import fitz

playbook_path = r'X:\Imperial Struggle\vassal_extracted\ImpStr_Living_Playbook_7-26-20.pdf'

print("="*80)
print("PLAYBOOK PDF")
print("="*80)
doc = fitz.open(playbook_path)
print(f"Pages: {len(doc)}")
for i in range(len(doc)):
    print(f"\n--- PLAYBOOK PAGE {i+1} ---")
    print(doc[i].get_text())
doc.close()
