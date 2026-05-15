from PIL import Image
img = Image.open(r'X:\Imperial Struggle\godot_project\assets\board\Imperial Struggle Map_Final-150-Clean.png')
W, H = img.size
# West African coast & asiento
img.crop((W//2, H*2//5, W*3//5, H*3//4)).save(r'X:\Imperial Struggle\map_wafrica.png')
print("Done")
