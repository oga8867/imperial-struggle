from PIL import Image
img = Image.open(r'X:\Imperial Struggle\godot_project\assets\board\Imperial Struggle Map_Final-150-Clean.png')
W, H = img.size
# Far west NA
img.crop((0, 0, W//3, H//2+200)).save(r'X:\Imperial Struggle\map_NA_west.png')
# East NA
img.crop((W//4, H//4, W//2+200, H//2+300)).save(r'X:\Imperial Struggle\map_NA_east.png')
# Caribbean east (Pirate Havens area)
img.crop((W//3, H//2+50, W//2+400, H-50)).save(r'X:\Imperial Struggle\map_carib_east.png')
print("Done")
