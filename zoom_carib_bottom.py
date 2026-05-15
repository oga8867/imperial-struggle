from PIL import Image
img = Image.open(r'X:\Imperial Struggle\godot_project\assets\board\Imperial Struggle Map_Final-150-Clean.png')
W, H = img.size
img.crop((600, H*2//3, W//2+200, H-50)).save(r'X:\Imperial Struggle\map_carib_bottom.png')
# Slaving contracts area near Asiento
img.crop((W//3, H//2-100, W//2+400, H*3//4)).save(r'X:\Imperial Struggle\map_asiento.png')
print("Done")
