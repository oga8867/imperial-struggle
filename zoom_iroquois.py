from PIL import Image
img = Image.open(r'X:\Imperial Struggle\godot_project\assets\board\Imperial Struggle Map_Final-150-Clean.png')
W, H = img.size
img.crop((0, 700, 1200, H//2+400)).save(r'X:\Imperial Struggle\map_iroquois_area.png')
img.crop((W//3+200, H//2-100, W//2+400, H-300)).save(r'X:\Imperial Struggle\map_carib_pirate_havens.png')
print("Done")
