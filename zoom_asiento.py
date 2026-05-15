from PIL import Image
img = Image.open(r'X:\Imperial Struggle\godot_project\assets\board\Imperial Struggle Map_Final-150-Clean.png')
W, H = img.size
# Asiento area - bottom right of Caribbean - look around 60-75% width
img.crop((1900, H*3//5, 3200, H*9//10)).save(r'X:\Imperial Struggle\map_asiento2.png')
print("Done")
