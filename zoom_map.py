from PIL import Image
img = Image.open(r'X:\Imperial Struggle\godot_project\assets\board\Imperial Struggle Map_Final-150-Clean.png')
print(f"Size: {img.size}")
# Crop into 4 quadrants
W, H = img.size
# Top-left (NA)
img.crop((0, 0, W//2+50, H//2+50)).save(r'X:\Imperial Struggle\map_NA.png')
img.crop((W//2-50, 0, W, H//2+50)).save(r'X:\Imperial Struggle\map_EU.png')
img.crop((0, H//2-50, W//2+50, H)).save(r'X:\Imperial Struggle\map_Caribbean.png')
img.crop((W//2-50, H//2-50, W, H)).save(r'X:\Imperial Struggle\map_India.png')
print("Done")
