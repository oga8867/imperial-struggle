from PIL import Image
img = Image.open(r'X:\Imperial Struggle\godot_project\assets\board\Imperial Struggle Map_Final-150-Clean.png')
W, H = img.size
# Slaving Contracts area should be around Asiento - check bottom right of Caribbean / Africa area
img.crop((W//2, H*5//8, W*3//4, H-50)).save(r'X:\Imperial Struggle\map_slaving.png')
print("Done")
