from PIL import Image
img = Image.open(r'X:\Imperial Struggle\godot_project\assets\board\Imperial Struggle Map_Final-150-Clean.png')
W, H = img.size
# More zoomed Europe - more central
img.crop((W//2+200, 200, W-100, H//2+100)).save(r'X:\Imperial Struggle\map_EU_zoom.png')
# Caribbean zoom
img.crop((600, H//2, W//2+300, H-100)).save(r'X:\Imperial Struggle\map_Caribbean_zoom.png')
# India zoom
img.crop((W//2+700, H//2, W-100, H-200)).save(r'X:\Imperial Struggle\map_India_zoom.png')
# NA zoom
img.crop((400, 100, W//2+200, H//2+200)).save(r'X:\Imperial Struggle\map_NA_zoom.png')
print("Done")
