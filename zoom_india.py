from PIL import Image
img = Image.open(r'X:\Imperial Struggle\godot_project\assets\board\Imperial Struggle Map_Final-150-Clean.png')
W, H = img.size
# Whole India region
img.crop((W//2+400, H//2-100, W-100, H-50)).save(r'X:\Imperial Struggle\map_India_full.png')
# Bottom of India
img.crop((W//2+400, H*3//4, W-100, H-50)).save(r'X:\Imperial Struggle\map_India_bottom.png')
print("Done")
